(module
 (data (offset (i32.const 10000))
  "\00\00\00\00\00\00\00\00\F3\02\00\00\F0\9F\8D\81\00\00\00\03\00\00\00\00\F3\01\00\00)\00\00\02\00\00\00\00\00\00\00\00\F3\01\00\00, \00\01\00\00\00\00\00\00\00\00\F3\02\00\00\F0\9F\8C\B3(\00\00\02\00\00\00\00\F3\01\00\00\0A\00\00\02\00\00\00\00\00\00\00\00")
 (import "spectest" "print_i32" (func $printi (param $i i32)))
 (import "spectest" "print_char" (func $printc (param $i i32)))
 (memory $rael.memory (export "memory") 1)
 (global $rael.HEAP_BASE (export "rael_heap_base") i32 (i32.const 20480))
 (global $rael.INIT (mut i32) (i32.const 0))
 (global $rael.WSIZE i32 (i32.const 4))
 (global $rael.MIN_BLOCK_SIZE i32 (i32.const 16))
 (global $rael.ALIGNMENT i32 (i32.const 8))
 (global $rael.TAG_USED i32 (i32.const 1))
 (global $rael.TAG_PRECEDING_USED i32 (i32.const 2))
 (global $rael.PAGE_SIZE i32 (i32.const 65536))
 (func $rael.set_free_list_head (param $addr i32)
  (i32.store (global.get $rael.HEAP_BASE) (local.get $addr)))
 (func $rael.get_free_list_head (result i32)
  (i32.load (global.get $rael.HEAP_BASE)))
 (func $rael.get_header (param $block i32) (result i32)
  (i32.load (local.get $block)))
 (func $rael.set_header (param $block i32) (param $val i32)
  (i32.store (local.get $block) (local.get $val)))
 (func $rael.get_next (param $block i32) (result i32)
  (i32.load offset=4 (local.get $block)))
 (func $rael.set_next (param $block i32) (param $val i32)
  (i32.store offset=4 (local.get $block) (local.get $val)))
 (func $rael.get_prev (param $block i32) (result i32)
  (i32.load offset=8 (local.get $block)))
 (func $rael.set_prev (param $block i32) (param $val i32)
  (i32.store offset=8 (local.get $block) (local.get $val)))
 (func $rael.extract_preceding_used_tag (param $header i32) (result i32)
  (i32.and (local.get $header) (global.get $rael.TAG_PRECEDING_USED)))
 (func $rael.extract_size (param $x i32) (result i32)
  (i32.and (local.get $x)
   (i32.xor (i32.sub (global.get $rael.ALIGNMENT) (i32.const 1))
    (i32.const -1))))
 (func $rael.extract_used_tag (param $header i32) (result i32)
  (i32.and (local.get $header) (global.get $rael.TAG_USED)))
 (func $rael.init_allocator (result i32) (local $all i32)
  (local $reserved i32) (local $usable i32)
  (local.set $all (i32.const 65536))
  (local.set $reserved (global.get $rael.HEAP_BASE))
  (local.set $usable (i32.sub (local.get $all) (local.get $reserved)))
  (call $rael.set_free_list_head
   (i32.add (global.get $rael.HEAP_BASE) (global.get $rael.WSIZE)))
  (i32.store offset=4 (global.get $rael.HEAP_BASE)
   (i32.or
    (i32.sub (local.get $usable)
     (i32.mul (i32.const 2) (global.get $rael.WSIZE)))
    (global.get $rael.TAG_PRECEDING_USED)))
  (i32.store offset=8 (global.get $rael.HEAP_BASE) (i32.const 0))
  (i32.store offset=12 (global.get $rael.HEAP_BASE) (i32.const 0))
  (i32.store
   (i32.sub (i32.add (global.get $rael.HEAP_BASE) (local.get $usable))
    (i32.mul (i32.const 2) (global.get $rael.WSIZE)))
   (i32.load (i32.add (global.get $rael.HEAP_BASE) (global.get $rael.WSIZE))))
  (i32.store
   (i32.sub (i32.add (global.get $rael.HEAP_BASE) (local.get $usable))
    (i32.mul (i32.const 1) (global.get $rael.WSIZE)))
   (global.get $rael.TAG_USED))
  (i32.const 0))
 (func $rael.search_free_list (param $req_size i32) (result i32)
  (local $free_block i32)
  (local.set $free_block (call $rael.get_free_list_head))
  (loop $loop
   (if (i32.ne (local.get $free_block) (i32.const 0))
    (then
     (if
      (i32.ge_u
       (call $rael.extract_size
        (call $rael.get_header (local.get $free_block)))
       (local.get $req_size))
      (then (return (local.get $free_block)))
      (else
       (local.set $free_block (call $rael.get_next (local.get $free_block)))))
     (br $loop))))
  (return (i32.const 0)))
 (func $rael.insert_free_block (param $free_block i32) (local $old_head i32)
  (local.set $old_head (call $rael.get_free_list_head))
  (call $rael.set_next (local.get $free_block) (local.get $old_head))
  (if (i32.ne (local.get $old_head) (i32.const 0))
   (then (call $rael.set_prev (local.get $old_head) (local.get $free_block))))
  (call $rael.set_prev (local.get $free_block) (i32.const 0))
  (call $rael.set_free_list_head (local.get $free_block)))
 (func $rael.remove_free_block (param $free_block i32) (local $next_free i32)
  (local $prev_free i32)
  (local.set $next_free (call $rael.get_next (local.get $free_block)))
  (local.set $prev_free (call $rael.get_prev (local.get $free_block)))
  (if (i32.ne (local.get $next_free) (i32.const 0))
   (then (call $rael.set_prev (local.get $next_free) (local.get $prev_free))))
  (if (i32.eq (local.get $free_block) (call $rael.get_free_list_head))
   (then (call $rael.set_free_list_head (local.get $next_free)))
   (else (call $rael.set_next (local.get $prev_free) (local.get $next_free)))))
 (func $rael.coalesce_free_block (param $old_block i32)
  (local $block_cursor i32) (local $new_block i32) (local $free_block i32)
  (local $old_size i32) (local $new_size i32) (local $tmp_size i32)
  (local.set $old_size
   (call $rael.extract_size (call $rael.get_header (local.get $old_block))))
  (local.set $new_size (local.get $old_size))
  (local.set $block_cursor (local.get $old_block))
  (if
   (i32.eq
    (call $rael.extract_preceding_used_tag
     (call $rael.get_header (local.get $block_cursor)))
    (i32.const 0))
   (then
    (local.set $tmp_size
     (call $rael.extract_size
      (i32.load (i32.sub (local.get $block_cursor) (global.get $rael.WSIZE)))))
    (local.set $free_block
     (i32.sub (local.get $block_cursor) (local.get $tmp_size)))
    (call $rael.remove_free_block (local.get $free_block))
    (local.set $new_size
     (i32.add (local.get $new_size) (local.get $tmp_size)))
    (local.set $block_cursor (local.get $free_block))))
  (local.set $new_block (local.get $block_cursor))
  (local.set $block_cursor
   (i32.add (local.get $old_block) (local.get $old_size)))
  (if
   (i32.eq
    (call $rael.extract_used_tag
     (call $rael.get_header (local.get $block_cursor)))
    (i32.const 0))
   (then
    (local.set $tmp_size
     (call $rael.extract_size
      (call $rael.get_header (local.get $block_cursor))))
    (call $rael.remove_free_block (local.get $block_cursor))
    (local.set $new_size
     (i32.add (local.get $new_size) (local.get $tmp_size)))
    (local.set $block_cursor
     (i32.add (local.get $block_cursor) (local.get $tmp_size)))))
  (if (i32.ne (local.get $new_block) (local.get $old_size))
   (then (call $rael.remove_free_block (local.get $old_block))
    (call $rael.set_header (local.get $new_block)
     (i32.or (local.get $new_size) (global.get $rael.TAG_PRECEDING_USED)))
    (i32.store (i32.sub (local.get $block_cursor) (global.get $rael.WSIZE))
     (i32.or (local.get $new_size) (global.get $rael.TAG_PRECEDING_USED)))
    (call $rael.insert_free_block (local.get $new_block)))))
 (func $rael.request_more_space (param $req_size i32) (local $n i32)
  (local $old i32) (local $new_block i32) (local $total_size i32)
  (local $prev_last_word_mask i32) (local $new_header i32)
  (local $footer i32) (local $end_of_heap i32)
  (local.set $n
   (i32.div_u
    (i32.sub (i32.add (local.get $req_size) (global.get $rael.PAGE_SIZE))
     (i32.const 1))
    (global.get $rael.PAGE_SIZE)))
  (local.set $old (memory.grow (local.get $n)))
  (local.set $new_block
   (i32.sub (i32.mul (local.get $old) (global.get $rael.PAGE_SIZE))
    (global.get $rael.WSIZE)))
  (local.set $total_size
   (i32.mul (local.get $n) (global.get $rael.PAGE_SIZE)))
  (local.set $prev_last_word_mask
   (call $rael.extract_preceding_used_tag
    (call $rael.get_header (local.get $new_block))))
  (local.set $new_header
   (i32.or (local.get $total_size) (local.get $prev_last_word_mask)))
  (call $rael.set_header (local.get $new_block) (local.get $new_header))
  (local.set $footer
   (i32.sub (i32.add (local.get $new_block) (local.get $total_size))
    (global.get $rael.WSIZE)))
  (i32.store (local.get $footer) (local.get $new_header))
  (local.set $end_of_heap
   (i32.add (local.get $new_block) (local.get $total_size)))
  (i32.store (local.get $end_of_heap) (global.get $rael.TAG_USED))
  (call $rael.insert_free_block (local.get $new_block))
  (call $rael.coalesce_free_block (local.get $new_block)))
 (func $rael.malloc (param $size i32) (result i32) (local $req_size i32)
  (local $ptr_free_block i32) (local $block_size i32)
  (local $preceding_block_use_tag i32) (local $new_header i32)
  (local $header_p i32) (local $footer_p i32) (local $following_block i32)
  (if (i32.eqz (global.get $rael.INIT))
   (then (call $rael.init_allocator)
    (if (i32.eqz) (then (global.set $rael.INIT (i32.const 1))))))
  (if (i32.eq (local.get $size) (i32.const 0)) (then (return (i32.const 0))))
  (local.set $size (i32.add (local.get $size) (global.get $rael.WSIZE)))
  (if (i32.lt_u (local.get $size) (global.get $rael.MIN_BLOCK_SIZE))
   (then (local.set $req_size (global.get $rael.MIN_BLOCK_SIZE)))
   (else
    (local.set $req_size
     (i32.mul (global.get $rael.ALIGNMENT)
      (i32.div_u
       (i32.sub (i32.add (local.get $size) (global.get $rael.ALIGNMENT))
        (i32.const 1))
       (global.get $rael.ALIGNMENT))))))
  (local.set $ptr_free_block
   (call $rael.search_free_list (local.get $req_size)))
  (if (i32.eq (local.get $ptr_free_block) (i32.const 0))
   (then (call $rael.request_more_space (local.get $req_size))
    (local.set $ptr_free_block
     (call $rael.search_free_list (local.get $req_size)))))
  (local.set $block_size
   (call $rael.extract_size
    (call $rael.get_header (local.get $ptr_free_block))))
  (call $rael.remove_free_block (local.get $ptr_free_block))
  (if
   (i32.ge_u (i32.sub (local.get $block_size) (local.get $req_size))
    (global.get $rael.MIN_BLOCK_SIZE))
   (then
    (local.set $preceding_block_use_tag
     (call $rael.extract_preceding_used_tag
      (call $rael.get_header (local.get $ptr_free_block))))
    (call $rael.set_header (local.get $ptr_free_block)
     (i32.or
      (i32.or (local.get $req_size) (local.get $preceding_block_use_tag))
      (global.get $rael.TAG_USED)))
    (local.set $new_header
     (i32.or (i32.sub (local.get $block_size) (local.get $req_size))
      (global.get $rael.TAG_PRECEDING_USED)))
    (local.set $header_p
     (i32.add (local.get $ptr_free_block) (local.get $req_size)))
    (i32.store (local.get $header_p) (local.get $new_header))
    (local.set $footer_p
     (i32.sub (i32.add (local.get $ptr_free_block) (local.get $block_size))
      (global.get $rael.WSIZE)))
    (i32.store (local.get $footer_p) (local.get $new_header))
    (call $rael.insert_free_block (local.get $header_p)))
   (else
    (local.set $following_block
     (i32.add (local.get $ptr_free_block) (local.get $block_size)))
    (call $rael.set_header (local.get $following_block)
     (i32.or (call $rael.get_header (local.get $following_block))
      (global.get $rael.TAG_PRECEDING_USED)))
    (call $rael.set_header (local.get $ptr_free_block)
     (i32.or (call $rael.get_header (local.get $ptr_free_block))
      (global.get $rael.TAG_USED)))))
  (return (i32.add (local.get $ptr_free_block) (global.get $rael.WSIZE))))
 (func $rael.gc.malloc (param $n i32) (result i32) (local $result i32)
  (call $rael.malloc (i32.add (i32.const 4) (local.get $n))))
 (func $rael.get_tag (param $p i32) (result i32)
  (i32.and (i32.load offset=0 (local.get $p)) (i32.const 0xFF)))
 (func $rael.set_tag (param $p i32) (param $tag i32)
  (i32.store offset=0 (local.get $p)
   (i32.or
    (i32.and (i32.load offset=0 (local.get $p)) (i32.const 0xFFFFFF00))
    (local.get $tag))))
 (func $rael.get_len (param $p i32) (result i32)
  (i32.shr_u (i32.load offset=0 (local.get $p)) (i32.const 8)))
 (func $rael.set_len (param $p i32) (param $len i32)
  (i32.store offset=0 (local.get $p)
   (i32.or
    (i32.and (i32.load offset=0 (local.get $p)) (i32.const 0x000000FF))
    (i32.shl (local.get $len) (i32.const 8)))))
 (func $rael.string_length (param $str i32) (result i32) (local $n i32)
  (local.set $n
   (i32.mul (call $rael.get_len (local.get $str)) (i32.const 4)))
  (i32.sub
   (i32.sub (local.get $n)
    (i32.load8_u offset=3 (i32.add (local.get $str) (local.get $n))))
   (i32.const 1)))
 (func $rael.string_item (param $str i32) (param $index i32) (result i32)
  (i32.load8_u offset=4 (i32.add (local.get $str) (local.get $index))))
 (func $rael.output_string (param $str i32) (local $counter i32)
  (loop $loop
   (if
    (i32.lt_s (local.get $counter)
     (call $rael.string_length (local.get $str)))
    (then
     (call $printc
      (call $rael.string_item (local.get $str) (local.get $counter)))
     (local.set $counter (i32.add (local.get $counter) (i32.const 1)))
     (br $loop))
    (else))))
 (table $rael.global funcref (elem))
 (func $gen_tree.fn/3 (export "moonapp/lib::gen_tree") (param $n/1 i32)
  (result i32) (local $x/2 i32) (local $ptr/17 i32) (local $ptr/18 i32)
  (local $ptr/19 i32) (local $ptr/20 i32) (local.get $n/1) (local.set $x/2)
  (block $join:3
   (block $join:4
    (block $join:5 (local.get $x/2) (i32.const 0) (i32.eq)
     (if (result i32) (then (br $join:5))
      (else (local.get $x/2) (i32.const 1) (i32.eq)
       (if (result i32) (then (br $join:4)) (else (br $join:3)))))
     (return))
    (i32.const 10000) (return))
   (i32.const 4) (call $rael.gc.malloc) (local.tee $ptr/17) (i32.const 1)
   (call $rael.set_tag) (local.get $ptr/17) (i32.const 1)
   (call $rael.set_len) (local.get $ptr/17) (i32.const 12)
   (call $rael.gc.malloc) (local.tee $ptr/18) (i32.const 0)
   (call $rael.set_tag) (local.get $ptr/18) (i32.const 3)
   (call $rael.set_len) (local.get $ptr/18) (i32.const 1)
   (i32.store offset=4) (local.get $ptr/18) (i32.const 0)
   (call $gen_tree.fn/3) (i32.store offset=8) (local.get $ptr/18)
   (i32.const 10000) (i32.store offset=12) (local.get $ptr/18)
   (i32.store offset=4) (local.get $ptr/17) (return))
  (i32.const 4) (call $rael.gc.malloc) (local.tee $ptr/19) (i32.const 1)
  (call $rael.set_tag) (local.get $ptr/19) (i32.const 1) (call $rael.set_len)
  (local.get $ptr/19) (i32.const 12) (call $rael.gc.malloc)
  (local.tee $ptr/20) (i32.const 0) (call $rael.set_tag) (local.get $ptr/20)
  (i32.const 3) (call $rael.set_len) (local.get $ptr/20) (local.get $n/1)
  (i32.store offset=4) (local.get $ptr/20) (local.get $n/1) (i32.const 1)
  (i32.sub) (call $gen_tree.fn/3) (i32.store offset=8) (local.get $ptr/20)
  (local.get $n/1) (i32.const 2) (i32.sub) (call $gen_tree.fn/3)
  (i32.store offset=12) (local.get $ptr/20) (i32.store offset=4)
  (local.get $ptr/19))
 (func $print_tree.fn/2
  (export "moonapp/lib::@moonapp/lib.IntTree::print_tree")
  (param $self/6 i32) (result i32) (local $x/7 i32) (local $l/9 i32)
  (local $n/10 i32) (local $r/11 i32) (local $x/13 i32) (local $x/14 i32)
  (local $x/15 i32) (local $x/16 i32) (local $tag/21 i32) (local.get $self/6)
  (local.set $x/7)
  (block $join:8
   (block $join:12 (local.get $x/7) (call $rael.get_tag) (local.set $tag/21)
    (if (result i32) (i32.eq (local.get $tag/21) (i32.const 0))
     (then (br $join:12))
     (else (local.get $x/7) (i32.load offset=4) (local.tee $x/13)
      (i32.load offset=4) (local.set $x/14) (local.get $x/13)
      (i32.load offset=8) (local.set $x/15) (local.get $x/13)
      (i32.load offset=12) (local.set $x/16) (local.get $x/15)
      (local.get $x/14) (local.get $x/16) (local.set $r/11) (local.set $n/10)
      (local.set $l/9) (br $join:8)))
    (return))
   (i32.const 10008) (call $rael.output_string) (i32.const 0) (return))
  (i32.const 10056) (call $rael.output_string) (local.get $n/10)
  (call $printi) (i32.const 10040) (call $rael.output_string)
  (local.get $l/9) (call $print_tree.fn/2) (drop) (i32.const 10040)
  (call $rael.output_string) (local.get $r/11) (call $print_tree.fn/2) 
  (drop) (i32.const 10024) (call $rael.output_string) (i32.const 0))
 (func $run.fn/1 (export "moonapp/lib::run") (result i32)
  (block $block/23
   (loop $loop/22 (i32.const 1)
    (if
     (then (i32.const 10) (call $gen_tree.fn/3) (call $print_tree.fn/2)
      (drop) (i32.const 10072) (call $rael.output_string) (i32.const 0)
      (br $loop/22)))))
  (i32.const 0))
 (func $*init*/4 (call $run.fn/1) (drop)) (export "_start" (func $*init*/4)))
