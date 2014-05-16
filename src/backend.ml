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

type t = Llvm.llmodule

type gamma =
  | Value of LLVM.llvalue
  | Env of int
  | Glob of int

let c = LLVM.create_context ()
let m = LLVM.create_module c "Main"

let i8_type = LLVM.i8_type c
let i32_type = LLVM.i32_type c
let i64_type = LLVM.i64_type c
let star_type = LLVM.pointer_type i8_type
let env_type = LLVM.pointer_type star_type
let lambda_type = LLVM.function_type star_type [|star_type; env_type|]
let closure_type = LLVM.struct_type c [|LLVM.pointer_type lambda_type; env_type|]
let variant_type = LLVM.struct_type c [|i32_type; env_type|]
let array_type = LLVM.array_type star_type
let array_ptr_type size = LLVM.pointer_type (array_type size)

let i64 = LLVM.const_int i64_type
let i32 = LLVM.const_int i32_type
let null = LLVM.const_null star_type
let undef = LLVM.undef star_type

let create_closure f env builder =
  let closure = LLVM.build_malloc closure_type "closure" builder in
  let loaded = LLVM.build_load closure "closure_loaded" builder in
  let loaded = LLVM.build_insertvalue loaded f 0 "closure_insert_f" builder in
  let loaded = LLVM.build_insertvalue loaded env 1 "closure_insert_env" builder in
  LLVM.build_store loaded closure builder;
  closure

let env_size_of_gamma gamma =
  let aux _ = function
    | Env _ -> succ
    | Value _ | Glob _ -> identity
  in
  Gamma.Value.fold aux gamma 0

let env_append param old_env size builder =
  let new_env = LLVM.build_malloc (array_type (succ size)) "" builder in
  let old_env = LLVM.build_bitcast old_env (array_ptr_type size) "" builder in
  let new_env_loaded = LLVM.build_load new_env "" builder in
  let new_env_filled =
    if Int.equal size 0 then
      LLVM.build_insertvalue new_env_loaded param size "" builder
    else
      let old_env = LLVM.build_load old_env "" builder in
      let rec loop array i =
        if Int.(i < size) then
          let old_value = LLVM.build_extractvalue old_env i "" builder in
          let array = LLVM.build_insertvalue array old_value i "" builder in
          loop array (succ i)
        else
          LLVM.build_insertvalue array param i "" builder
      in
      loop new_env_loaded 0
  in
  LLVM.build_store new_env_filled new_env builder;
  LLVM.build_gep new_env [|i64 0; i64 0|] "" builder

let rec llvalue_of_pattern_var value builder = function
  | Pattern.VLeaf -> value
  | Pattern.VNode (i, var) ->
      let value =
        LLVM.build_bitcast value (LLVM.pointer_type variant_type) "" builder
      in
      let value = LLVM.build_load value "" builder in
      let value = LLVM.build_extractvalue value 1 "" builder in
      let value = LLVM.build_gep value [|i32 i|] "" builder in
      let value = LLVM.build_load value "" builder in
      llvalue_of_pattern_var value builder var

let rec create_branch func env gamma value term results (constr, tree) =
  let gamma = match constr with
    | UntypedTree.Constr _ -> gamma
    | UntypedTree.Any name -> Gamma.Value.add name (Value term) gamma
  in
  let block = LLVM.append_block c "" func in
  let builder = LLVM.builder_at_end c block in
  ignore (create_tree func env gamma builder value results tree);
  block

and create_result func ~env ~globals gamma result =
  let block = LLVM.append_block c "" func in
  let builder = LLVM.builder_at_end c block in
  ignore (lambda func ~env ~globals gamma builder result);
  block

and create_tree func env gamma builder value results =
  function
  | UntypedTree.Leaf i ->
      let block = List.nth results i in
      LLVM.build_br block builder
  | UntypedTree.Node (var, cases) ->
      (* The more general case is always the first one
         (as it has been reversed in Pattern.create)
      *)
      let cases = List.rev cases in
      let (default, cases) = match cases with
        | x::xs -> (x, xs)
        | [] -> assert false
      in
      let term = llvalue_of_pattern_var value builder var in
      let default_branch = create_branch func env gamma value term results default in
      let switch = LLVM.build_switch term default_branch (List.length cases) builder in
      List.iter
        (fun ((constr, _) as case) ->
           let i = match constr with
             | UntypedTree.Constr i -> i
             | UntypedTree.Any _ -> assert false
           in
           let branch = create_branch func env gamma value term results case in
           LLVM.add_case switch (i32 i) branch
        )
        cases;
      switch

and lambda func ~env ~globals gamma builder = function
  | UntypedTree.Abs (name, t) ->
      let (f, builder') = LLVM.define_function c "__lambda" lambda_type m in
      LLVM.set_linkage LLVM.Linkage.Internal f;
      let closure = create_closure f env builder in
      let builder = builder' in
      let param = LLVM.param f 0 in
      let env = LLVM.param f 1 in
      let env_size = env_size_of_gamma gamma in
      let env = env_append param env env_size builder in
      let gamma = Gamma.Value.add name (Value param) gamma in
      let gamma = Gamma.Value.add name (Env env_size) gamma in
      let v = lambda f ~env ~globals gamma builder t in
      LLVM.build_ret v builder;
      closure
  | UntypedTree.App (f, x) ->
      let boxed_f = lambda func ~env ~globals gamma builder f in
      let boxed_f = LLVM.build_bitcast boxed_f (LLVM.pointer_type closure_type) "extract_f_cast" builder in
      let boxed_f = LLVM.build_load boxed_f "exctract_f" builder in
      let f = LLVM.build_extractvalue boxed_f 0 "f" builder in
      let env_f = LLVM.build_extractvalue boxed_f 1 "env" builder in
      let x = lambda func ~env ~globals gamma builder x in
      LLVM.build_call f [|x; env_f|] "tmp" builder
  | UntypedTree.PatternMatching (t, results, tree) ->
      let t = lambda func ~env ~globals gamma builder t in
      let results = List.map (create_result func ~env ~globals gamma) results in
      create_tree func env gamma builder t results tree
  | UntypedTree.Val name ->
      let value = Gamma.Value.find name gamma in
      let value = Option.default_delayed (fun () -> assert false) value in
      begin match value with
      | Value value -> value
      | Env i ->
          let env = LLVM.build_bitcast env (array_ptr_type (succ i)) "" builder in
          let value = LLVM.build_load env "" builder in
          LLVM.build_extractvalue value i "" builder
      | Glob i ->
          let value = LLVM.build_load globals "" builder in
          LLVM.build_extractvalue value i "" builder
      end
  | UntypedTree.Variant i ->
      let variant = LLVM.build_malloc variant_type "variant" builder in
      let variant_loaded = LLVM.build_load variant "variant_loaded" builder in
      let variant_loaded = LLVM.build_insertvalue variant_loaded (i32 i) 0 "variant_with_idx" builder in
      let variant_loaded = LLVM.build_insertvalue variant_loaded env 1 "variant_with_vals" builder in
      LLVM.build_store variant_loaded variant builder;
      variant

let store_to_globals ~globals x i builder =
  let globals_loaded = LLVM.build_load globals "" builder in
  let globals_loaded = LLVM.build_insertvalue globals_loaded x i "" builder in
  LLVM.build_store globals_loaded globals builder

let rec init func ~globals gamma global_values builder = function
  | `Val (name, i, t) :: xs ->
      let value = lambda func ~env:null ~globals gamma builder t in
      let gamma = Gamma.Value.add name (Glob i) gamma in
      let global_values = Gamma.Value.add name value global_values in
      store_to_globals ~globals value i builder;
      init func ~globals gamma global_values builder xs
  | `Rec (name, i, t) :: xs ->
      let gamma = Gamma.Value.add name (Glob i) gamma in
      let value = lambda func ~env:null ~globals gamma builder t in
      let global_values = Gamma.Value.add name value global_values in
      store_to_globals ~globals value i builder;
      init func ~globals gamma global_values builder xs
  | `Bind (name, value, i) :: xs ->
      let gamma = Gamma.Value.add name (Glob i) gamma in
      let value = LLVM.build_load value "" builder in
      let global_values = Gamma.Value.add name value global_values in
      store_to_globals ~globals value i builder;
      init func ~globals gamma global_values builder xs
  | [] ->
      (* TODO: Use global (needs a real build-system) *)
      let aux name value =
        let name = Gamma.Name.to_string name in
        let global = LLVM.define_global name null m in
        LLVM.build_store value global builder;
      in
      Gamma.Value.iter aux global_values

let create_globals size =
  let initial_value =
    let value = Array.make size null in
    LLVM.const_array star_type value
  in
  let globals = LLVM.define_global "globals" initial_value m in
  LLVM.set_linkage LLVM.Linkage.Internal globals;
  globals

let make ~with_main =
  let rec top init_list i gamma = function
    | UntypedTree.Value (name, t) :: xs ->
        top (`Val (name, i, t) :: init_list) (succ i) gamma xs
    | UntypedTree.RecValue (name, t) :: xs ->
        top (`Rec (name, i, t) :: init_list) (succ i) gamma xs
    | UntypedTree.Binding (name, binding) :: xs ->
        let v = LLVM.bind c ~name binding m in
        top (`Bind (name, v, i) :: init_list) (succ i) gamma xs
    | [] ->
        let ty = LLVM.function_type (LLVM.void_type c) [||] in
        let (f, builder) = LLVM.define_function c "__init" ty m in
        let globals = create_globals i in
        init f ~globals gamma Gamma.Value.empty builder (List.rev init_list);
        LLVM.build_ret_void builder;
        if with_main then begin
          let (_, builder) = LLVM.define_function c "main" ty m in
          ignore (LLVM.build_call f [||] "" builder);
          LLVM.build_ret_void builder;
        end;
        m
  in
  top [] 0 Gamma.Value.empty

let link dst src =
  Llvm_linker.link_modules dst src Llvm_linker.Mode.DestroySource;
  dst

let init = lazy (Llvm_all_backends.initialize ())

let get_triple () =
  Lazy.force init;
  Llvm_target.Target.default_triple ()

let get_target ~triple =
  let target = Llvm_target.Target.by_triple triple in
  Llvm_target.TargetMachine.create ~triple target

let optimize ~opt ~lto m =
  let triple = get_triple () in
  let target = get_target ~triple in
  let layout = Llvm_target.TargetMachine.data_layout target in
  LLVM.set_target_triple triple m;
  LLVM.set_data_layout (Llvm_target.DataLayout.as_string layout) m;
  LLVM.optimize ~lto ~opt layout m;
  m

let to_string = Llvm.string_of_llmodule

let write_bitcode ~o m = Llvm_bitwriter.write_bitcode_file m o

let emit_object_file ~tmp m =
  let triple = get_triple () in
  let target = get_target ~triple in
  Llvm_target.TargetMachine.emit_to_file
    m
    Llvm_target.CodeGenFileType.ObjectFile
    tmp
    target
