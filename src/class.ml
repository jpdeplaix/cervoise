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

type name = Ident.Name.t
type ty_name = Ident.Type.t

module Instances = PrivateTypes.Instances

(* TODO: Handle contraints *)
type t = PrivateTypes.class_t =
  { params : (ty_name * Kinds.t) list
  ; signature : (name * PrivateTypes.t) list
  ; instances : name Instances.t
  }

let create params signature =
  { params
  ; signature
  ; instances = Instances.empty
  }

let remove_module_aliases = PrivateTypes.class_remove_module_aliases
let equal = PrivateTypes.class_equal

let get_params ~loc f gamma args self =
  try
    let aux (gamma, args) (_, k) = function
      | UnsugaredTree.Param name ->
          let gamma = Gamma.add_type name (PrivateTypes.Abstract k) gamma in
          (gamma, PrivateTypes.Param (name, k) :: args)
      | UnsugaredTree.Filled ty ->
          let loc = fst ty in
          let (ty, k') = f gamma ty in
          if not (Kinds.equal k k') then
            Kinds.Err.fail ~loc ~has:k' ~expected:k;
          (gamma, PrivateTypes.Filled ty :: args)
    in
    let (gamma, args) = List.fold_left2 aux (gamma, []) self.params args in
    (gamma, List.rev args)
  with
  | Invalid_argument _ ->
      Err.fail
        ~loc
        "Wrong number of parameter. Has %d but expected %d"
        (List.length args)
        (List.length self.params)

let get_instance_name ~loc tys self =
  match Instances.find tys self.instances with
  | Some x -> x
  | None ->
      Err.fail ~loc "No instance found for '???'" (* TODO: Fill ??? *)
