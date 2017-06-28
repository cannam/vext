
structure AnyLibControl :> LIB_CONTROL = struct

    structure H = LibControlFn(HgControl)
    structure G = LibControlFn(GitControl)

    fun review context (spec as { vcs, ... } : libspec) =
        (fn HG => H.review | GIT => G.review) vcs context spec

    fun status context (spec as { vcs, ... } : libspec) =
        (fn HG => H.status | GIT => G.status) vcs context spec

    fun update context (spec as { vcs, ... } : libspec) =
        (fn HG => H.update | GIT => G.update) vcs context spec
end

fun load_libspec spec_json lock_json libname : libspec =
    let open JsonBits
        val libobj   = lookup_mandatory spec_json ["libs", libname]
        val vcs      = lookup_mandatory_string libobj ["vcs"]
        val retrieve = lookup_optional_string libobj
        val service  = retrieve ["service"]
        val owner    = retrieve ["owner"]
        val repo     = retrieve ["repository"]
        val url      = retrieve ["url"]
        val branch   = retrieve ["branch"]
        val user_pin = retrieve ["pin"]
        val lock_pin = case lookup_optional lock_json ["libs", libname] of
                           SOME ll => lookup_optional_string ll ["pin"]
                         | NONE => NONE
    in
        {
          libname = libname,
          vcs = case vcs of
                    "hg" => HG
                  | "git" => GIT
                  | other => raise Fail ("Unknown version-control system \"" ^
                                         other ^ "\""),
          source = case (url, service, owner, repo) of
                       (SOME u, NONE, _, _) => URL_SOURCE u
                     | (NONE, SOME ss, owner, repo) =>
                       SERVICE_SOURCE { service = ss, owner = owner, repo = repo }
                     | _ => raise Fail ("Must have exactly one of service " ^
                                        "or url string"),
          pin = case lock_pin of
                    SOME p => PINNED p
                  | NONE =>
                    case user_pin of
                        SOME p => PINNED p
                      | NONE => UNPINNED,
          branch = case branch of
                       SOME b => BRANCH b
                     | NONE => DEFAULT_BRANCH
        }
    end  

fun load_userconfig () : userconfig =
    let val home = FileBits.homedir ()
        val conf_json = 
            JsonBits.load_json_from
                (OS.Path.joinDirFile {
                      dir = home,
                      file = VextFilenames.user_config_file })
            handle IO.Io _ => Json.OBJECT []
    in
        {
          accounts = case JsonBits.lookup_optional conf_json ["accounts"] of
                         NONE => []
                       | SOME (Json.OBJECT aa) =>
                         map (fn (k, (Json.STRING v)) =>
                                 { service = k, login = v }
                             | _ => raise Fail
                                          "String expected for account name")
                             aa
                       | _ => raise Fail "Array expected for accounts",
          providers = Provider.load_providers conf_json
        }
    end

fun load_project (userconfig : userconfig) rootpath use_locks : project =
    let val spec_file = FileBits.project_spec_path rootpath
        val lock_file = FileBits.project_lock_path rootpath
        val _ = if OS.FileSys.access (spec_file, [OS.FileSys.A_READ])
                   handle OS.SysErr _ => false
                then ()
                else raise Fail ("Failed to open project spec file " ^
                                 (VextFilenames.project_file) ^ " in " ^
                                 rootpath ^
                                 ".\nPlease ensure the spec file is in the " ^
                                 "project root and run this from there.")
        val spec_json = JsonBits.load_json_from spec_file
        val lock_json = if use_locks
                        then JsonBits.load_json_from lock_file
                             handle IO.Io _ => Json.OBJECT []
                        else Json.OBJECT []
        val extdir = JsonBits.lookup_mandatory_string spec_json
                                                      ["config", "extdir"]
        val spec_libs = JsonBits.lookup_optional spec_json ["libs"]
        val lock_libs = JsonBits.lookup_optional lock_json ["libs"]
        val providers = Provider.load_more_providers
                            (#providers userconfig) spec_json
        val libnames = case spec_libs of
                           NONE => []
                         | SOME (Json.OBJECT ll) => map (fn (k, v) => k) ll
                         | _ => raise Fail "Object expected for libs"
    in
        {
          context = {
            rootpath = rootpath,
            extdir = extdir,
            providers = providers,
            accounts = #accounts userconfig
          },
          libs = map (load_libspec spec_json lock_json) libnames
        }
    end

fun save_lock_file rootpath locks =
    let val lock_file = FileBits.project_lock_path rootpath
        open Json
        val lock_json =
            OBJECT [
                ("libs", OBJECT
                             (map (fn { libname, id_or_tag } =>
                                      (libname,
                                       OBJECT [ ("pin", STRING id_or_tag) ]))
                                  locks))
            ]
    in
        JsonBits.save_json_to lock_file lock_json
    end
        
fun pad_to n str =
    if n <= String.size str then str
    else pad_to n (str ^ " ")

fun hline_to 0 = ""
  | hline_to n = "-" ^ hline_to (n-1)

val libname_width = 25
val libstate_width = 11
val localstate_width = 9
val notes_width = 5
val divider = " | "

fun print_status_header () =
    print ("\r" ^ pad_to 80 "" ^ "\n " ^
           pad_to libname_width "Library" ^ divider ^
           pad_to libstate_width "State" ^ divider ^
           pad_to localstate_width "Local" ^ divider ^
           "Notes" ^ "\n " ^
           hline_to libname_width ^ "-+-" ^
           hline_to libstate_width ^ "-+-" ^
           hline_to localstate_width ^ "-+-" ^
           hline_to notes_width ^ "\n")

fun print_outcome_header () =
    print ("\r" ^ pad_to 80 "" ^ "\n " ^
           pad_to libname_width "Library" ^ divider ^
           pad_to libstate_width "Outcome" ^ divider ^
           "Notes" ^ "\n " ^
           hline_to libname_width ^ "-+-" ^
           hline_to libstate_width ^ "-+-" ^
           hline_to notes_width ^ "\n")
                        
fun print_status with_network (libname, status) =
    let val libstate_str =
            case status of
                OK (ABSENT, _) => "Absent"
              | OK (CORRECT, _) => if with_network then "Correct" else "Present"
              | OK (SUPERSEDED, _) => "Superseded"
              | OK (WRONG, _) => "Wrong"
              | ERROR _ => "Error"
        val localstate_str =
            case status of
                OK (_, MODIFIED) => "Modified"
              | OK (_, UNMODIFIED) => "Clean"
              | _ => ""
        val error_str =
            case status of
                ERROR e => e
              | _ => ""
    in
        print (" " ^
               pad_to libname_width libname ^ divider ^
               pad_to libstate_width libstate_str ^ divider ^
               pad_to localstate_width localstate_str ^ divider ^
               error_str ^ "\n")
    end

fun print_update_outcome (libname, outcome) =
    let val outcome_str =
            case outcome of
                OK id => "Ok"
              | ERROR e => "Failed"
        val error_str =
            case outcome of
                ERROR e => e
              | _ => ""
    in
        print (" " ^
               pad_to libname_width libname ^ divider ^
               pad_to libstate_width outcome_str ^ divider ^
               error_str ^ "\n")
    end

fun act_and_print action print_header print_line (libs : libspec list) =
    let val lines = map (fn lib => (#libname lib, action lib)) libs
        val _ = print_header ()
    in
        app print_line lines;
        lines
    end

fun return_code_for outcomes =
    foldl (fn ((_, result), acc) =>
              case result of
                  ERROR _ => OS.Process.failure
                | _ => acc)
          OS.Process.success
          outcomes
        
fun status_of_project ({ context, libs } : project) =
    return_code_for (act_and_print (AnyLibControl.status context)
                                   print_status_header (print_status false)
                                   libs)
                                             
fun review_project ({ context, libs } : project) =
    return_code_for (act_and_print (AnyLibControl.review context)
                                   print_status_header (print_status true)
                                   libs)

fun update_project ({ context, libs } : project) =
    let val outcomes = act_and_print
                           (AnyLibControl.update context)
                           print_outcome_header print_update_outcome libs
        val locks =
            List.concat
                (map (fn (libname, result) =>
                         case result of
                             ERROR _ => []
                           | OK id => [{ libname = libname, id_or_tag = id }])
                     outcomes)
        val return_code = return_code_for outcomes
    in
        if OS.Process.isSuccess return_code
        then save_lock_file (#rootpath context) locks
        else ();
        return_code
    end

fun load_local_project use_locks =
    let val userconfig = load_userconfig ()
        val rootpath = OS.FileSys.getDir ()
    in
        load_project userconfig rootpath use_locks
    end    

fun with_local_project use_locks f =
    let val return_code = f (load_local_project use_locks)
                          handle e =>
                                 (print ("Failed with exception: " ^
                                         (exnMessage e) ^ "\n");
                                  OS.Process.failure)
        val _ = print "\n";
    in
        return_code
    end
        
fun review () = with_local_project false review_project
fun status () = with_local_project false status_of_project
fun update () = with_local_project false update_project
fun install () = with_local_project true update_project

fun version () =
    (print ("v" ^ vext_version ^ "\n");
     OS.Process.success)
                      
fun usage () =
    (print "\nVext ";
     version ();
     print ("\nA simple manager for third-party source code dependencies.\n\n"
            ^ "Usage:\n\n"
            ^ "  vext <command>\n\n"
            ^ "where <command> is one of:\n\n"
            ^ "  status   print quick report on local status only, without using network\n"
            ^ "  review   check configured libraries against their providers, and report\n"
            ^ "  install  update configured libraries according to project specs and lock file\n"
            ^ "  update   update configured libraries and lock file according to project specs\n"
            ^ "  version  print the Vext version number and exit\n\n");
    OS.Process.failure)

fun vext args =
    let val return_code = 
            case args of
                ["review"] => review ()
              | ["status"] => status ()
              | ["install"] => install ()
              | ["update"] => update ()
              | ["version"] => version ()
              | _ => usage ()
    in
        OS.Process.exit return_code;
        ()
    end
        
fun main () =
    vext (CommandLine.arguments ())
