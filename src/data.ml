(*************************************************************************)
(*                                                                       *)
(*                              OCamlClean                               *)
(*                                                                       *)
(*                             Benoit Vaugon                             *)
(*                                                                       *)
(*    This file is distributed under the terms of the CeCILL license.    *)
(*    See file ../LICENSE-en.                                            *)
(*                                                                       *)
(*************************************************************************)

exception Exn of string

let parse ic index =
  let offset, _ =
    try Index.find_section index Index.Data
    with Not_found -> raise (Exn "code section not found")
  in
  seek_in ic offset;
  let (data : Obj.t array) = input_value ic in
  data

let clean code orig_data =
  let nb_data = Array.length orig_data in
  let nb_instr = Array.length code in
  let map = Array.make nb_data None in
  let invmap = Array.make nb_data 0 in
  let counter = ref 12 in
  let remap p =
    match map.(p) with
    | None ->
        let new_p = !counter in
        counter := succ new_p;
        map.(p) <- Some new_p;
        invmap.(new_p) <- p;
        new_p
    | Some new_p -> new_p
  in
  for i = 0 to !counter - 1 do
    map.(i) <- Some i;
    invmap.(i) <- i
  done;
  for i = 0 to nb_instr - 1 do
    match code.(i) with
    | Instr.Getglobal p -> code.(i) <- Instr.Getglobal (remap p)
    | Instr.Getglobalfield (p, n) ->
        code.(i) <- Instr.Getglobalfield (remap p, n)
    | _ -> ()
  done;
  for i = 0 to nb_instr - 1 do
    match code.(i) with
    | Instr.Setglobal p -> (
        match map.(p) with
        | None -> code.(i) <- Instr.Nop
        | Some new_p -> code.(i) <- Instr.Setglobal new_p)
    | _ -> ()
  done;
  let new_data = Array.init !counter (fun p -> orig_data.(invmap.(p))) in
  new_data

let export_c oc data = C_util.output_data_string oc (Marshal.to_string data [])

let print data =
  let open Printf in
  let open Obj in
  let ctr = ref 0 in
  let out x =
    printf "%d: %s\n%!" !ctr x;
    incr ctr
  in
  Array.iter
    (fun d ->
      match (is_block d, is_int d) with
      | true, false -> (
          match tag d with
          | t when t = string_tag -> out (sprintf "string: %s" (Obj.magic d))
          | t when t = int_tag -> out (sprintf "int: %d" (Obj.magic d))
          | t when t = custom_tag -> out "custom"
          | t when t = 0 -> out (sprintf "block: %d" (size d))
          | _ -> out "XXX")
      | false, true -> out (sprintf "int:%d" (Obj.magic d))
      | _ -> Printf.printf "unknown block\n%!")
    data

let parse_c ic =
  let rec scan_until s =
    let line = input_line ic in
    if line = s then () else scan_until s
  in
  let scan_bytes s1 s2 =
    let buf = Buffer.create 128 in
    scan_until s1;
    let rec loop () =
      let line = input_line ic in
      if line <> s2 then (
        let bits = Str.(split (regexp_string ", ") line) in
        List.iter
          (fun n -> Buffer.add_char buf (Char.chr (int_of_string n)))
          bits;
        loop ())
      else Buffer.contents buf
    in
    loop ()
  in
  let data_buf = scan_bytes "static char caml_data[] = {" "};" in
  let (data : Obj.t array) = Marshal.from_string data_buf 0 in
  let sec_buf = scan_bytes "static char caml_sections[] = {" "};" in
  let (sections : (string * Obj.t) list) = Marshal.from_string sec_buf 0 in
  let prim_buf : string = Obj.magic (List.assoc "PRIM" sections) in
  (* Primitive strings are NUL-separated *)
  let prims = Array.of_list Str.(split (regexp_string "\000") prim_buf) in
  (data, prims)
