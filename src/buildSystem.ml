(*
Copyright (c) 2013-2015 Jacques-Pascal Deplaix <jp.deplaix@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*)

open Monomorphic_containers.Open

exception Failure

type import_data =
  { library : bool
  ; hash_import : string
  }

type impl_infos =
  { version : string
  ; hash : string
  ; hash_bc : string
  ; imports : (string * import_data) list
  }

let map_msgpack_maps =
  let aux = function
    | (`FixRaw name, value) -> (String.of_list name, value)
    | _ -> raise Failure
  in
  List.map aux

let parse_impl_infos file =
  let content = CCIO.read_all file in
  match Msgpack.Serialize.deserialize_string content with
    | `FixMap l ->
        begin match map_msgpack_maps l with
        | [ ("version", `FixRaw version)
          ; ("hash", `Raw16 hash)
          ; ("hash-bc", `Raw16 hash_bc)
          ; ("imports", `Map32 imports)
          ] ->
            let version = String.of_list version in
            let hash = String.of_list hash in
            let hash_bc = String.of_list hash_bc in
            let imports =
              let aux = function
                | (`Raw16 import, `FixMap l) ->
                    begin match map_msgpack_maps l with
                    | [ ("library", `Bool library)
                      ; ("hash", `Raw16 hash_import)
                      ] ->
                        let hash_import = String.of_list hash_import in
                        (String.of_list import, {library; hash_import})
                    | _ ->
                        raise Failure
                    end
                | _ ->
                    raise Failure
              in
              List.map aux imports
            in
            {version; hash; hash_bc; imports}
        | _ ->
            raise Failure
        end
    | _ ->
        raise Failure

let check_imports_hash options =
  let aux (modul, {library; hash_import}) =
    let modul =
      if library then
        Module.library_from_string options modul
      else
        Module.from_string options modul
    in
    let hash_file = Digest.file (Module.impl_infos modul) in
    if not (String.equal hash_file hash_import) then
      raise Failure;
    modul
  in
  List.map aux

let check_impl options modul =
  try
    let infos = Module.impl_infos modul in
    let infos = Utils.CCIO.with_in infos (parse_impl_infos) in
    let hash = Digest.file (Module.impl modul) in
    let hash_bc = Digest.file (Module.cimpl modul) in
    if not
         (String.equal infos.version Config.version
          && String.equal infos.hash hash
          && String.equal infos.hash_bc hash_bc
         )
    then
      raise Failure;
    check_imports_hash options infos.imports
  with
  | _ -> raise Failure

let write_impl_infos imports modul =
  let version = Config.version in
  let hash = Digest.file (Module.impl modul) in
  let hash_bc = Digest.file (Module.cimpl modul) in
  let imports =
    let aux modul =
      let import = Module.to_string modul in
      let library = Module.is_library modul in
      let hash_import = Digest.file (Module.impl_infos modul) in
      let data =
        `FixMap
          [ (`FixRaw (String.to_list "library"), `Bool library)
          ; (`FixRaw (String.to_list "hash"), `Raw16 (String.to_list hash_import))
          ]
      in
      (`Raw16 (String.to_list import), data)
    in
    List.map aux imports
  in
  let content =
    `FixMap
      [ (`FixRaw (String.to_list "version"), `FixRaw (String.to_list version))
      ; (`FixRaw (String.to_list "hash"), `Raw16 (String.to_list hash))
      ; (`FixRaw (String.to_list "hash-bc"), `Raw16 (String.to_list hash_bc))
      ; (`FixRaw (String.to_list "imports"), `Map32 imports)
      ]
  in
  let content = Msgpack.Serialize.serialize_string content in
  let file_name = Module.impl_infos modul in
  Utils.mkdir file_name;
  Utils.CCIO.with_out file_name (fun file -> output_string file content)
