(*
 * Copyright (c) 2013-2014 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Core_kernel.Std

module L = Log.Make(struct let section = "VALUE" end)

exception Conflict
exception Invalid of string

module type S = sig
  include Identifiable.S
  val to_json: t -> Ezjsonm.t
  val of_json: Ezjsonm.t -> t
  val of_bytes: string -> t option
  val of_bytes_exn: string -> t
  val merge: old:t option -> t -> t -> t
end

module String  = struct

  include String

  let of_json = IrminMisc.json_decode_exn

  let to_json = IrminMisc.json_encode

  let of_bytes s = Some s

  let of_bytes_exn s = s

  let merge ~old t1 t2 =
    match compare t1 t2 with
    | 0 -> t1
    | _ ->
      match old with
      | None     -> raise Conflict
      | Some old ->
        match compare old t1 with
        | 0 -> t2
        | _ ->
          match compare old t2 with
          | 0 -> t1
          | _ -> raise Conflict

end

module JSON = struct

  module M = struct
    type t =
      [ `Null
      | `Bool of bool
      | `Float of float
      | `String of string
      | `A of t list
      | `O of (string * t) list ]
    with bin_io, compare, sexp
    let hash (t : t) = Hashtbl.hash t
    include Sexpable.To_stringable (struct type nonrec t = t with sexp end)
    let module_name = "Tree"
  end
  include M
  include Identifiable.Make (M)

  let rec encode t: Ezjsonm.t =
    match t with
    | `Null
    | `Bool _
    | `Float _  -> t
    | `String s -> IrminMisc.json_encode s
    | `A l      -> `A (List.rev_map ~f:encode l)
    | `O l      -> `O (List.rev_map ~f:(fun (k,v) -> k, encode v) l)

  let to_json = encode

  let rec decode t: Ezjsonm.t =
    match t with
    | `Null
    | `Bool _
    | `Float _
    | `String _ -> t
    | `A l      -> `A (List.rev_map ~f:decode l)
    | `O l      ->
      match IrminMisc.json_decode t with
      | Some s -> `String s
      | None   -> `O (List.rev_map ~f:(fun (k,v) -> k, encode v) l)

  let of_json = decode

  let of_bytes s =
    try Some (Ezjsonm.from_string s)
    with Ezjsonm.Parse_error _ -> None

  let of_bytes_exn s =
    Ezjsonm.from_string s

  (* XXX: replace by a clever merge function *)
  let merge ~old t1 t2 =
    let old = match old with
      | None   -> None
      | Some o -> Some (Ezjsonm.to_string o) in
    let str =
      String.merge ~old (Ezjsonm.to_string t1) (Ezjsonm.to_string t2) in
    match of_bytes str with
    | Some j -> j
    | None   -> raise Conflict

end

module type STORE = sig
  include IrminStore.AO
  module Key: IrminKey.S with type t = key
  module Value: S with type t = value
end

module Make
    (K: IrminKey.S)
    (C: S)
    (Contents: IrminStore.AO with type key = K.t and type value = C.t)
= struct
  include Contents
  module Key  = K
  module Value = C
end
