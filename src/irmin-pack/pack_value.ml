open! Import
include Pack_value_intf

module Kind = struct
  type t = Commit | Contents | Inode | Node

  let to_magic = function
    | Commit -> 'C'
    | Contents -> 'B'
    | Inode -> 'I'
    | Node -> 'N'

  let of_magic_exn = function
    | 'C' -> Commit
    | 'B' -> Contents
    | 'I' -> Inode
    | 'N' -> Node
    | c -> Fmt.failwith "Kind.of_magic: unexpected magic char %C" c

  let t = Irmin.Type.(map char) of_magic_exn to_magic
  let pp = Fmt.using to_magic Fmt.char
end

type ('h, 'a) value = { hash : 'h; kind : Kind.t; v : 'a } [@@deriving irmin]

module type S = S with type kind := Kind.t
module type Persistent = Persistent with type kind := Kind.t

module Make (Config : sig
  val selected_kind : Kind.t
  val length_header : length_header
end)
(Hash : Irmin.Hash.S)
(Key : T)
(Data : Irmin.Type.S) =
struct
  module Hash = Irmin.Hash.Typed (Hash) (Data)

  type t = Data.t [@@deriving irmin]
  type key = Key.t
  type hash = Hash.t

  let hash = Hash.hash
  let kind = Config.selected_kind

  let length_header =
    match Config.length_header with
    | None -> `Never
    | Some _ as x -> `Sometimes (Fun.const x)

  let value = [%typ: (Hash.t, Data.t) value]
  let encode_value = Irmin.Type.(unstage (encode_bin value))
  let decode_value = Irmin.Type.(unstage (decode_bin value))
  let encode_bin ~dict:_ ~offset:_ v hash = encode_value { kind; hash; v }

  let decode_bin ~dict:_ ~hash:_ s off =
    let t = decode_value s off in
    t.v

  type nonrec int = int [@@deriving irmin ~decode_bin]

  let decode_bin_length =
    match Irmin.Type.(Size.of_encoding value) with
    | Unknown ->
        Fmt.failwith "Type must have a recoverable encoded length: %a"
          Irmin.Type.pp_ty t
    | Static n -> fun _ _ -> n
    | Dynamic f -> f

  let kind _ = Config.selected_kind
end

module Of_contents (Conf : sig
  val contents_length_header : length_header
end) =
Make (struct
  let selected_kind = Kind.Contents
  let length_header = Conf.contents_length_header
end)

module Of_commit = Make (struct
  let selected_kind = Kind.Commit
  let length_header = None
end)
