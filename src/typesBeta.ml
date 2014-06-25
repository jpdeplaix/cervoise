(*
Copyright (c) 2013 Jacques-Pascal Deplaix <jp.deplaix@gmail.com>

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

open BatteriesExceptionless
open Monomorphic.None

type name = Ident.Type.t

type t =
  | Ty of name
  | Fun of (t * t)
  | Forall of (name * Kinds.t * t)
  | AbsOnTy of (name * Kinds.t * t)
  | AppOnTy of (t * t)

let fmt = Printf.sprintf

let rec replace ~from ~ty =
  let rec aux = function
    | Ty x when Ident.Type.equal x from -> ty
    | Ty _ as t -> t
    | Fun (param, ret) -> Fun (aux param, aux ret)
    | (AbsOnTy (x, _, _) as t)
    | (Forall (x, _, _) as t) when Ident.Type.equal x from -> t
    | Forall (x, k, t) -> Forall (x, k, aux t)
    | (AbsOnTy (x, _, _) as t) when Ident.Type.equal x from -> t
    | AbsOnTy (x, k, t) -> AbsOnTy (x, k, aux t)
    | AppOnTy (f, x) ->
        let x = aux x in
        begin match aux f with
        | AbsOnTy (from', _, t) -> replace ~from:from' ~ty:x t
        | (Ty _ as f)
        | (AppOnTy _ as f) -> AppOnTy (f, x)
        | Fun _
        | Forall _ -> assert false
        end
  in
  aux

let rec of_ty = function
  | Types.Ty (name, _) -> Ty name
  | Types.TyAlias (_, t) -> of_ty t
  | Types.Fun (p, r) -> Fun (of_ty p, of_ty r)
  | Types.Forall (name, k, t) -> Forall (name, k, of_ty t)
  | Types.AbsOnTy (name, k, t) -> AbsOnTy (name, k, of_ty t)
  | Types.AppOnTy (Types.AbsOnTy (name, _, t), x) ->
      let x = of_ty x in
      replace ~from:name ~ty:x (of_ty t)
  | Types.AppOnTy (f, x) ->
      AppOnTy (of_ty f, of_ty x)

let of_parse_tree_kind ~loc gammaT ty =
  let (ty, k) = Types.from_parse_tree ~loc gammaT ty in
  (of_ty ty, k)

let of_parse_tree ~loc gammaT ty =
  let (ty, k) = Types.from_parse_tree ~loc gammaT ty in
  if Kinds.not_star k then
    Error.fail ~loc "Values cannot be of kind /= '*'";
  of_ty ty

let func ~param ~res = Fun (param, res)
let forall ~param ~kind ~res = Forall (param, kind, res)

let rec to_string = function
  | Ty x -> Ident.Type.to_string x
  | Fun (Ty x, ret) -> Ident.Type.to_string x ^ " -> " ^ to_string ret
  | Fun (x, ret) -> "(" ^ to_string x ^ ") -> " ^ to_string ret
  | Forall (x, k, t) ->
      fmt "forall %s : %s. %s" (Ident.Type.to_string x) (Kinds.to_string k) (to_string t)
  | AbsOnTy (name, k, t) ->
      fmt "λ%s : %s. %s" (Ident.Type.to_string name) (Kinds.to_string k) (to_string t)
  | AppOnTy (Ty f, Ty x) -> fmt "%s %s" (Ident.Type.to_string f) (Ident.Type.to_string x)
  | AppOnTy (Ty f, x) -> fmt "%s (%s)" (Ident.Type.to_string f) (to_string x)
  | AppOnTy (f, Ty x) -> fmt "(%s) %s" (to_string f) (Ident.Type.to_string x)
  | AppOnTy (f, x) -> fmt "(%s) (%s)" (to_string f) (to_string x)

let equal x y =
  let rec aux eq_list = function
    | Ty x, Ty x' ->
        let eq = Ident.Type.equal in
        List.exists (fun (y, y') -> eq x y && eq x' y') eq_list
        || (eq x x' && List.for_all (fun (y, y') -> eq x y || eq x' y') eq_list)
    | Fun (param, res), Fun (param', res') ->
        aux eq_list (param, param') && aux eq_list (res, res')
    | AppOnTy (f, x), AppOnTy (f', x') ->
        aux eq_list (f, f') && aux eq_list (x, x')
    | AbsOnTy (name1, k1, t), AbsOnTy (name2, k2, t')
    | Forall (name1, k1, t), Forall (name2, k2, t') when Kinds.equal k1 k2 ->
        aux ((name1, name2) :: eq_list) (t, t')
    | AppOnTy _, _
    | AbsOnTy _, _
    | Forall _, _
    | Ty _, _
    | Fun _, _ -> false
  in
  aux [] (x, y)

let rec size = function
  | Fun (_, t) -> succ (size t)
  | AppOnTy _
  | AbsOnTy _
  | Ty _ -> 0
  | Forall (_, _, t) -> size t

let rec head = function
  | Ty name -> name
  | Fun (_, t)
  | Forall (_, _, t)
  | AbsOnTy (_, _, t)
  | AppOnTy (t, _) -> head t

module Error = struct
  let type_error_aux ~loc =
    Error.fail
      ~loc
      "Error: This expression has type '%s' but an \
       expression was expected of type '%s'"

  let fail ~loc ~has ~expected =
    type_error_aux ~loc (to_string has) (to_string expected)

  let function_type ~loc ty =
    Error.fail
      ~loc
      "Error: This expression has type '%s'. \
       This is not a function; it cannot be applied."
      (to_string ty)

  let forall_type ~loc ty =
    Error.fail
      ~loc
      "Error: This expression has type '%s'. \
       This is not a type abstraction; it cannot be applied by a value."
      (to_string ty)

  let kind_missmatch ~loc ~has ~on =
    Error.fail
      ~loc
      "Cannot apply something with kind '%s' on '%s'"
      (Kinds.to_string has)
      (Kinds.to_string on)
end

let apply ~loc = function
  | Fun x ->
      x
  | (Forall _ as ty)
  | (AppOnTy _ as ty)
  | (Ty _ as ty) ->
      Error.function_type ~loc ty
  | AbsOnTy _ ->
      assert false

let apply_ty ~loc ~ty_x ~kind_x = function
  | Forall (ty, k, res) when Kinds.equal k kind_x ->
      let res = replace ~from:ty ~ty:ty_x res in
      (ty, res)
  | Forall (_, k, _) ->
      Error.kind_missmatch ~loc ~has:kind_x ~on:k
  | (Fun _ as ty)
  | (AppOnTy _ as ty)
  | (Ty _ as ty) ->
      Error.forall_type ~loc ty
  | AbsOnTy _ ->
      assert false

let rec check_if_returns_type ~datatype = function
  | Ty x -> Ident.Type.equal x datatype
  | Forall (_, _, ret)
  | AppOnTy (ret, _)
  | Fun (_, ret) -> check_if_returns_type ~datatype ret
  | AbsOnTy _ -> false
