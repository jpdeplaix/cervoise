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

type t =
  | Star
  | Eff
  | KFun of (t * t)

let rec from_list = function
  | [] -> Star
  | k::ks -> KFun (k, from_list ks)

let rec to_string = function
  | Star -> "*"
  | Eff -> "φ"
  | KFun (p, r) -> to_string p ^ " -> " ^ to_string r

let rec equal x y = match x, y with
  | Eff, Eff
  | Star, Star -> true
  | KFun (p1, r1), KFun (p2, r2) -> equal p1 p2 && equal r1 r2
  | Star, _
  | KFun _, _
  | Eff, _ -> false

let not_star = function
  | Star -> false
  | KFun _ | Eff -> true

let is_effect = function
  | Eff -> true
  | Star | KFun _ -> false

module Err = struct
  let fail ~loc ~has ~expected =
    Err.fail
      ~loc
      "Error: This type has kind '%s' but a \
       type was expected of kind '%s'"
      (to_string has)
      (to_string expected)
end
