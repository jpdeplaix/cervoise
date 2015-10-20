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

type name = Ident.Name.t
type eff_name = Ident.Exn.t
type ty_size = int
type used_vars = (Pattern.var * name) list
type index = int
type arity = int
type length = int

type is_rec =
  | Rec
  | NonRec

type ('int, 'float, 'char, 'string) ty =
  | Int of 'int
  | Float of 'float
  | Char of 'char
  | String of 'string

type tag_ty = (unit, unit, unit, unit) ty

type const = (int, float, int, string) ty

type value = (name * is_rec * t)

and t =
  | Abs of (name * t)
  | App of (t * t)
  | Val of name
  | Var of (index * length)
  | PatternMatching of (t * (used_vars * t) list * Pattern.t)
  | Let of (value * t)
  | Fail of (eff_name * t list)
  | Try of (t * ((eff_name * name list) * t) list)
  | RecordGet of (t * int)
  | RecordCreate of t list
  | Const of const

and foreign_ret_type =
  | Void of t
  | Alloc of tag_ty

type foreign_fun_type = (foreign_ret_type * tag_ty list)

type top =
  | Value of value
  | Foreign of (string * name * foreign_fun_type)
  | Exception of eff_name
