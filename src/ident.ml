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

open BatteriesExceptionless
open Monomorphic.None

let fmt = Printf.sprintf

module Name = struct
  type t = (Location.t * string list)

  let compare (_, x) (_, y) = List.compare String.compare x y

  let equal (_, x) (_, y) = List.eq String.equal x y

  let prepend modul = function
    | (_, []) -> assert false
    | (loc, ([_] as x)) -> (loc, Module.to_list modul @ x)
    | x -> x

  let prepend_empty = function
    | (_, []) -> assert false
    | (loc, ([_] as x)) -> (loc, [""] @ x)
    | x -> x

  let of_list ~loc x = (loc, x)
  let to_string (_, name) = String.concat "." name

  let loc = fst

  let unique self n = match self with
    | (loc, [name]) ->
        (loc, [fmt "%s__%d" name n])
    | (_, _::_)
    | (_, []) -> assert false
end

module Type = Name

module Exn = Name

module Eff = Name
