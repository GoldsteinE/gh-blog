;; That's the whole file. I truncated Go ones, but this is small enough.
(module
  (type (;0;) (func (param i32) (result i32)))
  ;; Only one func in this file, inner func got inlined.
  (func $fib (type 0) (param i32) (result i32)
    (local i32 i32 i32)
    i32.const 1
    local.set 1
    i32.const 0
    local.set 2
    block  ;; label = @1
      block  ;; label = @2
        loop  ;; label = @3
          block  ;; label = @4
            local.get 0
            ;; Nice jump table!
            br_table 3 (;@1;) 2 (;@2;) 0 (;@4;)
          end
          local.get 1
          local.get 2
          i32.add
          local.set 3
          local.get 0
          i32.const -1
          i32.add
          local.set 0
          local.get 1
          local.set 2
          local.get 3
          local.set 1
          ;; This is clearly what's left of the recursive call.
          br 0 (;@3;)
        end
      end
      local.get 1
      local.set 2
    end
    local.get 2)
  (table (;0;) 1 1 funcref)
  (memory (;0;) 16)
  (global $__stack_pointer (mut i32) (i32.const 1048576))
  (global (;1;) i32 (i32.const 1048576))
  (global (;2;) i32 (i32.const 1048576))
  (export "memory" (memory 0))
  (export "fib" (func $fib))
  (export "__data_end" (global 1))
  (export "__heap_base" (global 2)))
