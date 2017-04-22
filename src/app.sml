
fun lookup_optional json kk =
    let fun lookup key =
            case json of
                Json.OBJECT kvs => (case List.find (fn (k, v) => k = key) kvs of
                                        SOME (k, v) => SOME v
                                      | NONE => NONE)
              | _ => raise Fail "Object expected"
    in
        case kk of
            [] => NONE
          | key::[] => lookup key
          | key::kk => case lookup key of
                           NONE => NONE
                         | SOME j => lookup_optional j kk
    end

fun lookup_mandatory json kk =
    case lookup_optional json kk of
        SOME v => v
      | NONE => raise Fail ("Config value is mandatory: " ^
                            (String.concatWith " -> " kk))
                   
fun lookup_mandatory_string json kk =
    case lookup_optional json kk of
        SOME (Json.STRING s) => s
      | _ => raise Fail ("Config value must be string: " ^
                         (String.concatWith " -> " kk))
                   
fun load_libspec json libname : libspec =
    let val libobj = lookup_mandatory json ["libs", libname]
    in
        {
          libname = libname,
          vcs = case lookup_mandatory_string libobj ["vcs"] of
                    "hg" => HG
                  | "git" => GIT
                  | other => raise Fail ("Unknown VCS \"" ^ other ^ "\""),
          provider = {
              (*!!! which mandatory, which optional? *)
              service = lookup_mandatory_string libobj ["provider", "service"],
              owner = lookup_mandatory_string libobj ["provider", "owner"],
              url = case lookup_optional libobj ["provider", "url"] of
                        SOME (Json.STRING u) => EXPLICIT u
                      | SOME _ => raise Fail "String expected for url"
                      | NONE => IMPLICIT
          },
          pin = case lookup_optional libobj ["pin"] of
                    SOME (Json.STRING p) => PINNED p
                  | SOME _ => raise Fail "String expected for pin"
                  | NONE => UNPINNED
        }
    end  

fun load_config rootpath : config =
    let val vexfile = FileBits.vexfile rootpath
        val _ = print ("path is " ^ rootpath ^ ", vex file is " ^ vexfile ^ "\n")
        val json = case Json.parse (FileBits.file_contents vexfile) of
                       Json.OK json => json
                     | Json.ERROR e => raise Fail e
        val extdir = lookup_mandatory_string json ["config", "extdir"]
        val libs = lookup_optional json ["libs"]
        val libnames = case libs of
                           NONE => []
                         | SOME (Json.OBJECT ll) => map (fn (k, v) => k) ll
                         | _ => raise Fail "Object expected for libs"
    in
        {
          context = {
            rootpath = rootpath,
            extdir = extdir
          },
          libs = map (load_libspec json) libnames
        }
    end

fun usage () =
    let open TextIO in
	output (stdErr,
	    "Usage:\n" ^
            "    vext <check|update>\n");
        raise Fail "Incorrect arguments specified"
    end

fun check config =
    let open AnyLibControl
        val outcomes = map (fn lib =>
                               (#libname lib, check (#context config) lib))
                           (#libs config)
    in
        app (fn (libname, ABSENT) => print ("ABSENT " ^ libname ^ "\n")
              | (libname, CORRECT) => print ("CORRECT " ^ libname ^ "\n")
              | (libname, SUPERSEDED) => print ("SUPERSEDED " ^ libname ^ "\n")
              | (libname, WRONG) => print ("WRONG " ^ libname ^ "\n"))
            outcomes
    end        

fun update config =
    let open AnyLibControl
        val outcomes = map (fn lib =>
                               (#libname lib, update (#context config) lib))
                           (#libs config)
    in
        app (fn (libname, OK) => print ("OK " ^ libname ^ "\n")
              | (libname, ERROR e) => print ("FAILED " ^ libname ^ ": " ^ e ^ "\n"))
            outcomes
    end        
       
fun main () =
    let (*!!! options: require that this program is in the root dir,
        and so use the location of this program as the root dir
        location; or require that the program is only ever run from
        the root dir; or use some mechanism to scan upwards in the dir
        hierarchy until we find a plausible root (e.g. a .vex file is
        present [and we are not within an ext dir?] *)
        val rootpath = FileBits.mydir ()
        val config = load_config rootpath
    in
        case CommandLine.arguments () of
            ["check"] => check config
          | ["update"] => update config
          | _ => usage ()
    end
    handle Fail err => print ("ERROR: " ^ err ^ "\n")
         | e => print ("Failed with exception: " ^ (exnMessage e) ^ "\n")