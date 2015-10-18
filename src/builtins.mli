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

val t_unit_name : [`UpperName of string list]

val unit : <lib_dir : string; ..> -> Ident.Type.t
val int : <lib_dir : string; ..> -> Ident.Type.t
val float : <lib_dir : string; ..> -> Ident.Type.t
val char : <lib_dir : string; ..> -> Ident.Type.t
val string : <lib_dir : string; ..> -> Ident.Type.t

val underscore : current_module:Module.t -> Ident.Name.t
val underscore_loc : current_module:Module.t -> Location.t -> Ident.Name.t
val underscore_instance_loc : current_module:Module.t -> Location.t -> Ident.Instance.t

val unknown_loc : Location.t

val exn : <lib_dir : string; ..> -> Ident.Type.t
val io : <lib_dir : string; ..> -> Ident.Type.t

val effects : <lib_dir : string; ..> -> Ident.Type.t list

val main : current_module:Module.t -> Ident.Name.t

val imports :
  no_prelude:bool ->
  <lib_dir : string; ..> ->
  (string list * Module.t) list ->
  (string list * Module.t) list

val tree :
  no_prelude:bool ->
  <lib_dir : string; ..> ->
  UnsugaredTree.top list ->
  UnsugaredTree.top list
