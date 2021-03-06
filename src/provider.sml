
structure Provider :> sig
    val load_providers : Json.json -> provider list
    val load_more_providers : provider list -> Json.json -> provider list
    val remote_url : context -> vcs -> source -> libname -> string
end = struct

    val known_providers : provider list =
        [ {
            service = "bitbucket",
            supports = [HG, GIT],
            remote_spec = {
                anon = SOME "https://bitbucket.org/{owner}/{repository}",
                auth = SOME "ssh://{vcs}@bitbucket.org/{owner}/{repository}"
            }
          },
          {
            service = "github",
            supports = [GIT],
            remote_spec = {
                anon = SOME "https://github.com/{owner}/{repository}",
                auth = SOME "ssh://{vcs}@github.com/{owner}/{repository}"
            }
          },
          { service = "sourcehut",
            supports = [HG, GIT],
            remote_spec = {
                anon = SOME "https://{vcs}.sr.ht/%7E{owner}/{repository}",
                auth = SOME "ssh://{vcs}@{vcs}.sr.ht/%7E{owner}/{repository}"
            }
          }
        ]

    fun vcs_name vcs =
        case vcs of HG => "hg"
                  | GIT => "git"
                  | SVN => "svn"
                                             
    fun vcs_from_name name =
        case name of "hg" => HG
                   | "git" => GIT 
                   | "svn" => SVN
                   | other => raise Fail ("Unknown vcs name \"" ^ name ^ "\"")

    fun load_more_providers previously_loaded json =
        let open JsonBits
            fun load pjson pname : provider =
                {
                  service = pname,
                  supports =
                  case lookup_mandatory pjson ["vcs"] of
                      Json.ARRAY vv =>
                      map (fn (Json.STRING v) => vcs_from_name v
                          | _ => raise Fail "Strings expected in vcs array")
                          vv
                    | _ => raise Fail "Array expected for vcs",
                  remote_spec = {
                      anon = lookup_optional_string pjson ["anonymous"],
                      auth = lookup_optional_string pjson ["authenticated"]
                  }
                }
            val loaded = 
                case lookup_optional json ["services"] of
                    NONE => []
                  | SOME (Json.OBJECT pl) => map (fn (k, v) => load v k) pl
                  | _ => raise Fail "Object expected for services in config"
            val newly_loaded =
                List.filter (fn p => not (List.exists (fn pp => #service p =
                                                                #service pp)
                                                      previously_loaded))
                            loaded
        in
            previously_loaded @ newly_loaded
        end

    fun load_providers json =
        load_more_providers known_providers json
                                                    
    fun expand_spec spec { vcs, service, owner, repo } login =
        (* ugly *)
        let fun replace str = 
                case str of
                    "vcs" => vcs_name vcs
                  | "service" => service
                  | "owner" =>
                    (case owner of
                         SOME ostr => ostr
                       | NONE => raise Fail ("Owner not specified for service " ^
                                             service))
                  | "repository" => repo
                  | "account" =>
                    (case login of
                         SOME acc => acc
                       | NONE => raise Fail ("Account not given for service " ^
                                             service))
                  | other => raise Fail ("Unknown variable \"" ^ other ^
                                         "\" in spec for service " ^ service)
            fun expand' acc sstr =
                case Substring.splitl (fn c => c <> #"{") sstr of
                    (pfx, sfx) =>
                    if Substring.isEmpty sfx
                    then rev (pfx :: acc)
                    else 
                        case Substring.splitl (fn c => c <> #"}") sfx of
                            (tok, remainder) =>
                            if Substring.isEmpty remainder
                            then rev (tok :: pfx :: acc)
                            else let val replacement =
                                         replace
                                             (* tok begins with "{": *)
                                             (Substring.string
                                                  (Substring.triml 1 tok))
                                 in
                                     expand' (Substring.full replacement ::
                                              pfx :: acc)
                                             (* remainder begins with "}": *)
                                             (Substring.triml 1 remainder)
                                 end
        in
            Substring.concat (expand' [] (Substring.full spec))
        end
        
    fun provider_url req login providers =
        case providers of
            [] => raise Fail ("Unknown service \"" ^ (#service req) ^
                              "\" for vcs \"" ^ (vcs_name (#vcs req)) ^ "\"")
          | ({ service, supports, remote_spec : remote_spec } :: rest) =>
            if service <> (#service req) orelse
               not (List.exists (fn v => v = (#vcs req)) supports)
            then provider_url req login rest
            else
                case (login, #auth remote_spec, #anon remote_spec) of
                    (SOME _, SOME auth, _) => expand_spec auth req login
                  | (SOME _, _, SOME anon) => expand_spec anon req NONE
                  | (NONE,   _, SOME anon) => expand_spec anon req NONE
                  | _ => raise Fail ("No suitable anonymous or authenticated " ^
                                     "URL spec provided for service \"" ^
                                     service ^ "\"")

    fun login_for ({ accounts, ... } : context) service =
        case List.find (fn a => service = #service a) accounts of
            SOME { login, ... } => SOME login
          | NONE => NONE

    fun reponame_for path =
        case String.tokens (fn c => c = #"/") path of
            [] => raise Fail "Non-empty library path required"
          | toks => hd (rev toks)
                        
    fun remote_url (context : context) vcs source libname =
        case source of
            URL_SOURCE u => u
          | SERVICE_SOURCE { service, owner, repo } =>
            provider_url { vcs = vcs,
                           service = service,
                           owner = owner,
                           repo = case repo of
                                      SOME r => r
                                    | NONE => reponame_for libname }
                         (login_for context service)
                         (#providers context)
end
