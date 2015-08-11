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

open UnsugaredTree

let new_upper_name_to_value ~current_module (loc, `NewUpperName name) =
  Ident.Name.create ~loc current_module name
let new_upper_name_to_type ~current_module (loc, `NewUpperName name) =
  Ident.Type.create ~loc current_module name
let new_upper_name_to_exn ~current_module (loc, `NewUpperName name) =
  Ident.Exn.create ~loc current_module name
let new_upper_name_to_tyclass ~current_module (loc, `NewUpperName name) =
  Ident.TyClass.create ~loc current_module name

let new_upper_name_to_local_type (loc, `NewUpperName name) =
  Ident.Type.local_create ~loc name

let get_module imports loc modul =
  let aux (k, _) = List.equal String.equal k modul in
  match List.find_pred aux imports with
  | None ->
      Err.fail ~loc "Unbound module %s" (String.concat "." modul)
  | Some (_, modul) ->
      modul

let transform_name imports loc local_f f = function
  | [] ->
      assert false
  | [name] ->
      local_f ~loc name
  | name ->
      let (modul, name) = Utils.detach_last name in
      let modul = get_module imports loc modul in
      f ~loc modul name

let upper_name_to_value imports (loc, `UpperName name) =
  transform_name imports loc Ident.Name.local_create Ident.Name.create name
let upper_name_to_type imports (loc, `UpperName name) =
  transform_name imports loc Ident.Type.local_create Ident.Type.create name
let upper_name_to_exn imports (loc, `UpperName name) =
  transform_name imports loc Ident.Exn.local_create Ident.Exn.create name
let upper_name_to_tyclass imports (loc, `UpperName name) =
  transform_name imports loc Ident.TyClass.local_create Ident.TyClass.create name

let lower_name_to_value imports (loc, `LowerName name) =
  transform_name imports loc Ident.Name.local_create Ident.Name.create name

let new_lower_name_to_value ~current_module ~allow_underscore = function
  | (loc, `NewLowerName name) ->
      Ident.Name.create ~loc current_module name
  | (loc, `Underscore) when allow_underscore ->
      Builtins.underscore_loc ~current_module loc
  | (loc, `Underscore) ->
      Err.fail ~loc "Wildcards are not allowed here"

let unsugar_kind = Option.get Kinds.Star

let unsugar_eff imports (loc, l) =
  let aux (name, args) =
    let name = upper_name_to_type imports name in
    let args = List.map (upper_name_to_exn imports) args in
    (name, args)
  in
  (loc, List.map aux l)

let rec unsugar_tyclass_arg imports = function
  | ParseTree.Param name -> Param (new_upper_name_to_local_type name)
  | ParseTree.Filled ty -> Filled (unsugar_ty imports ty)

and unsugar_tyclass imports (name, args) =
  let name = upper_name_to_tyclass imports name in
  let args = List.map (unsugar_tyclass_arg imports) args in
  (name, args)

and unsugar_ty imports =
  let unsugar_forall ~loc ty args =
    let rec aux = function
      | (name, k) :: xs ->
          let name = new_upper_name_to_local_type name in
          (loc, Forall ((name, unsugar_kind k), aux xs))
      | [] ->
          unsugar_ty imports ty
    in
    if List.is_empty args then
      assert false;
    aux args
  in
  let unsugar_absOnTy ~loc ty args =
    let rec aux = function
      | (name, k) :: xs ->
          let name = new_upper_name_to_local_type name in
          (loc, AbsOnTy ((name, unsugar_kind k), aux xs))
      | [] ->
          unsugar_ty imports ty
    in
    if List.is_empty args then
      assert false;
    aux args
  in
  function
  | (loc, ParseTree.Fun (x, eff, y)) ->
      let eff = Option.map (unsugar_eff imports) eff in
      (loc, Fun (unsugar_ty imports x, eff, unsugar_ty imports y))
  | (loc, ParseTree.Ty name) ->
      let name = upper_name_to_type imports name in
      (loc, Ty name)
  | (loc, ParseTree.Eff effects) ->
      let effects = unsugar_eff imports effects in
      (loc, Eff effects)
  | (loc, ParseTree.Forall (args, ty)) ->
      unsugar_forall ~loc ty args
  | (loc, ParseTree.TyClass (tyclass, eff, ty)) ->
      let tyclass = unsugar_tyclass imports tyclass in
      let eff = Option.map (unsugar_eff imports) eff in
      (loc, TyClass (tyclass, eff, unsugar_ty imports ty))
  | (loc, ParseTree.AbsOnTy (args, ty)) ->
      unsugar_absOnTy ~loc ty args
  | (loc, ParseTree.AppOnTy (x, y)) ->
      (loc, AppOnTy (unsugar_ty imports x, unsugar_ty imports y))

let unsugar_annot imports (annot, eff) =
  let eff = Option.map (unsugar_eff imports) eff in
  (unsugar_ty imports annot, eff)

let unsugar_sig ~current_module imports (name, ty) =
  let name = new_lower_name_to_value ~current_module ~allow_underscore:false name in
  let ty = unsugar_ty imports ty in
  (name, ty)

let rec unsugar_pattern ~current_module imports = function
  | ParseTree.TyConstr (loc, name, args) ->
      let name = upper_name_to_value imports name in
      TyConstr (loc, name, List.map (unsugar_pattern ~current_module imports) args)
  | ParseTree.Any name ->
      let name = new_lower_name_to_value ~current_module ~allow_underscore:true name in
      Any name

let unsugar_tyclass_app_arg imports = function
  | ParseTree.TyClassVariable name ->
      TyClassVariable (lower_name_to_value imports name)
  | ParseTree.TyClassInstance (name, tys) ->
      TyClassInstance (upper_name_to_tyclass imports name, List.map (unsugar_ty imports) tys)

let rec unsugar_pat ~current_module imports options (pattern, t) =
  (unsugar_pattern ~current_module imports pattern, unsugar_t ~current_module imports options t)

(* TODO: Allow full patterns but restrict here *)
and unsugar_try_pattern ~current_module imports options (pattern, t) =
  let pattern =
    (upper_name_to_exn imports (fst pattern),
     List.map (new_lower_name_to_value ~current_module ~allow_underscore:true) (snd pattern)
    )
  in
  (pattern, unsugar_t ~current_module imports options t)

and unsugar_t ~current_module imports options = function
  | (_, ParseTree.Abs (args, t)) ->
      if List.is_empty args then
        assert false;
      unsugar_args ~current_module imports options args t
  | (loc, ParseTree.App (f, x)) ->
      (loc, App (unsugar_t ~current_module imports options f, unsugar_t ~current_module imports options x))
  | (loc, ParseTree.TApp (t, ty)) ->
      (loc, TApp (unsugar_t ~current_module imports options t, unsugar_ty imports ty))
  | (loc, ParseTree.TyClassApp (t, x)) ->
      (loc, CApp (unsugar_t ~current_module imports options t, unsugar_tyclass_app_arg imports x))
  | (loc, ParseTree.LowerVal name) ->
      let name = lower_name_to_value imports name in
      (loc, Val name)
  | (loc, ParseTree.UpperVal name) ->
      let name = upper_name_to_value imports name in
      (loc, Val name)
  | (loc, ParseTree.PatternMatching (t, patterns)) ->
      (loc, PatternMatching (unsugar_t ~current_module imports options t, List.map (unsugar_pat ~current_module imports options) patterns))
  | (loc, ParseTree.Let ((name, is_rec, (args, x)), t)) ->
      let name = new_lower_name_to_value ~current_module ~allow_underscore:true name in
      (loc, Let ((name, is_rec, unsugar_args ~current_module imports options args x), unsugar_t ~current_module imports options t))
  | (loc, ParseTree.Fail (ty, (exn, args))) ->
      let exn = upper_name_to_exn imports exn in
      (loc, Fail (unsugar_ty imports ty, (exn, List.map (unsugar_t ~current_module imports options) args)))
  | (loc, ParseTree.Try (t, patterns)) ->
      (loc, Try (unsugar_t ~current_module imports options t, List.map (unsugar_try_pattern ~current_module imports options) patterns))
  | (loc, ParseTree.Seq (x, y)) ->
      let name = Builtins.underscore ~current_module in
      let ty = ((loc, Ty (Builtins.t_unit options)), None) in
      (loc, Let ((name, NonRec, (fst x, Annot (unsugar_t ~current_module imports options x, ty))), unsugar_t ~current_module imports options y))
  | (loc, ParseTree.Annot (t, ty)) ->
      (loc, Annot (unsugar_t ~current_module imports options t, unsugar_annot imports ty))

and unsugar_args ~current_module imports options args (annot, t) =
  let rec aux = function
    | (loc, ParseTree.VArg (name, ty)) :: xs ->
        let name = new_lower_name_to_value ~current_module ~allow_underscore:true name in
        let ty = unsugar_ty imports ty in
        let (ty_xs, xs) = aux xs in
        let ty_xs =
          let aux (ty_xs, eff) =
            let ty_xs = Fun (ty, eff, ty_xs) in
            ((loc, ty_xs), None)
          in
          Option.map aux ty_xs
        in
        (ty_xs, (loc, Abs ((name, ty), xs)))
    | (loc, ParseTree.TArg (name, k)) :: xs ->
        let name = new_upper_name_to_local_type name in
        let ty = (name, unsugar_kind k) in
        let (ty_xs, xs) = aux xs in
        let ty_xs =
          let aux (ty_xs, eff) =
            let ty_xs = Forall (ty, ty_xs) in
            ((loc, ty_xs), eff)
          in
          Option.map aux ty_xs
        in
        (ty_xs, (loc, TAbs (ty, xs)))
    | (loc, ParseTree.Unit) :: xs ->
        let x =
          ParseTree.VArg
            ((loc, `Underscore), (loc, ParseTree.Ty (loc, Builtins.t_unit_name)))
        in
        aux ((loc, x) :: xs)
    | (loc, ParseTree.TyClassArg (name, tyclass)) :: xs ->
        let name = new_lower_name_to_value ~current_module ~allow_underscore:true name in
        let tyclass = unsugar_tyclass imports tyclass in
        let (ty_xs, xs) = aux xs in
        let ty_xs =
          let aux (ty_xs, eff) =
            let ty_xs = TyClass (tyclass, eff, ty_xs) in
            ((loc, ty_xs), None)
          in
          Option.map aux ty_xs
        in
        (ty_xs, (loc, CAbs ((name, tyclass), xs)))
    | [] ->
        begin match annot with
        | Some annot ->
            let annot = unsugar_annot imports annot in
            (Some annot, (fst t, Annot (unsugar_t ~current_module imports options t, annot)))
        | None ->
            (None, unsugar_t ~current_module imports options t)
        end
  in
  match aux args with
  | (Some ty, t) -> (fst t, Annot (t, ty))
  | (None, t) -> t

let unsugar_variant ~current_module imports ~datatype ~args (ParseTree.Variant (name, tys)) =
  let name = new_upper_name_to_value ~current_module name in
  let tys = List.map (unsugar_ty imports) tys in
  let uloc = Builtins.unknown_loc in
  let ty =
    let rec aux = function
      | [] -> List.fold_left (fun ty (x, _) -> AppOnTy ((uloc, ty), (uloc, Ty x))) (Ty datatype) args
      | x::xs -> Fun (x, None, (uloc, aux xs))
    in
    List.fold_left (fun ty x -> Forall (x, (uloc, ty))) (aux tys) args
  in
  Variant (name, tys, (uloc, ty))

let unsugar_variants ~current_module imports ~datatype ~args =
  List.map (unsugar_variant ~current_module imports ~datatype ~args)

let unsugar_variant_args args =
  let aux (x, k) = (new_upper_name_to_local_type x, unsugar_kind k) in
  List.map aux args

let create ~current_module imports options = function
  | ParseTree.Value (name, is_rec, (args, (ty, t))) ->
      let name = new_lower_name_to_value ~current_module ~allow_underscore:false name in
      Value (name, is_rec, unsugar_args ~current_module imports options args (ty, t))
  | ParseTree.Type (name, ty) ->
      let name = new_upper_name_to_type ~current_module name in
      Type (name, unsugar_ty imports ty)
  | ParseTree.Binding (name, ty, content) ->
      let name = new_lower_name_to_value ~current_module ~allow_underscore:false name in
      Binding (name, unsugar_ty imports ty, content)
  | ParseTree.Datatype (name, args, variants) ->
      let kind = Kinds.from_list (List.map (fun (_, k) -> unsugar_kind k) args) in
      let name = new_upper_name_to_type ~current_module name in
      let args = unsugar_variant_args args in
      let variants = unsugar_variants ~current_module imports ~datatype:name ~args variants in
      Datatype (name, kind, args, variants)
  | ParseTree.Exception (name, tys) ->
      let name = new_upper_name_to_exn ~current_module name in
      Exception (name, List.map (unsugar_ty imports) tys)
  | ParseTree.Open (loc, `UpperName modul) ->
      let modul = get_module imports loc modul in
      Open modul
  | ParseTree.Class (name, params, sigs) ->
      let name = new_upper_name_to_tyclass ~current_module name in
      let params =
        let aux (name, k) =
          (new_upper_name_to_local_type name, unsugar_kind k)
        in
        List.map aux params
      in
      let sigs = List.map (unsugar_sig ~current_module imports) sigs in
      Class (name, params, sigs)

(* TODO: check "doublons" *)
let create_imports ~current_module options =
  let aux = function
    | ParseTree.Source (_, `UpperName name) ->
        (name, Module.create ~current_module name)
    | ParseTree.Library (_, `UpperName name) ->
        (name, Module.library_create options name)
  in
  List.map aux

let create ~no_prelude ~current_module options imports tree =
  let imports = create_imports ~current_module options imports in
  let imports = Builtins.imports ~no_prelude options imports in
  let tree = List.map (create ~current_module imports options) tree in
  let tree = Builtins.tree ~no_prelude options tree in
  (List.map snd imports, tree)

let create_interface ~current_module imports = function
  | ParseTree.IVal signature ->
      InterfaceTree.Val (unsugar_sig ~current_module imports signature)
  | ParseTree.IAbstractType (name, k) ->
      let name = new_upper_name_to_type ~current_module name in
      InterfaceTree.AbstractType (name, unsugar_kind k)
  | ParseTree.IDatatype (name, args, variants) ->
      let kind = Kinds.from_list (List.map (fun (_, k) -> unsugar_kind k) args) in
      let name = new_upper_name_to_type ~current_module name in
      let args = unsugar_variant_args args in
      let variants = unsugar_variants ~current_module imports ~datatype:name ~args variants in
      InterfaceTree.Datatype (name, kind, args, variants)
  | ParseTree.ITypeAlias (name, ty) ->
      let name = new_upper_name_to_type ~current_module name in
      InterfaceTree.TypeAlias (name, unsugar_ty imports ty)
  | ParseTree.IException (name, tys) ->
      let name = new_upper_name_to_exn ~current_module name in
      InterfaceTree.Exception (name, List.map (unsugar_ty imports) tys)
  | ParseTree.IOpen (loc, `UpperName modul) ->
      let modul = get_module imports loc modul in
      InterfaceTree.Open modul

let create_interface ~current_module options imports tree =
  let imports = create_imports ~current_module options imports in
  let tree = List.map (create_interface ~current_module imports) tree in
  (List.map snd imports, tree)
