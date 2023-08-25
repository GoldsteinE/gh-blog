;; The file is massively truncated because apparently GitHub doesn’t like 75MB source files or something.
(module
  ;; That’s the outer function.
  (func $main.fib (type 0) (param i32) (result i32)
    (local i32 i64 i64)
    global.get 0
    local.set 1
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          block  ;; label = @4
            local.get 0
            br_table 0 (;@4;) 0 (;@4;) 0 (;@4;) 0 (;@4;) 1 (;@3;) 2 (;@2;)
          end
          local.get 1
          global.get 2
          i32.wrap_i64
          i32.load offset=16
          i32.le_u
          if  ;; label = @4
            local.get 1
            i32.const 8
            i32.sub
            local.tee 1
            global.set 0
            local.get 1
            i64.const 356646912
            i64.store
            i32.const 0
            call $runtime.morestack_noctxt
            global.get 0
            local.set 1
            br_if 3 (;@1;)
          end
          local.get 1
          i32.const 56
          i32.sub
          local.tee 1
          global.set 0
          local.get 1
          i64.extend_i32_u
          i64.const 32
          i64.add
          i32.wrap_i64
          i64.const 0
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 40
          i64.add
          i32.wrap_i64
          i64.const 0
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 48
          i64.add
          i32.wrap_i64
          i64.const 0
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 40
          i64.add
          i32.wrap_i64
          i64.const 356712448
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 48
          i64.add
          i32.wrap_i64
          local.get 1
          i64.extend_i32_u
          i64.const 32
          i64.add
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 32
          i64.add
          i32.wrap_i64
          local.get 1
          i64.extend_i32_u
          i64.const 40
          i64.add
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 32
          i64.add
          i32.wrap_i64
          i64.load
          local.tee 2
          i64.eqz
          if  ;; label = @4
            local.get 1
            i32.const 8
            i32.sub
            local.tee 1
            global.set 0
            local.get 1
            i64.const 356646914
            i64.store
            i32.const 0
            call $runtime.sigpanic
            global.get 0
            local.set 1
            br_if 3 (;@1;)
          end
          local.get 2
          i32.wrap_i64
          i64.load
          local.set 3
          local.get 1
          local.get 1
          i64.load offset=64
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 8
          i64.add
          i32.wrap_i64
          i64.const 0
          i64.store
          local.get 1
          i64.extend_i32_u
          i64.const 16
          i64.add
          i32.wrap_i64
          i64.const 1
          i64.store
          local.get 2
          global.set 1
          local.get 3
          local.get 1
          i32.const 8
          i32.sub
          local.tee 1
          global.set 0
          local.get 1
          i64.const 356646916
          i64.store
          i32.wrap_i64
          i32.const 16
          i32.shr_u
          local.set 0
          i32.const 0
          local.get 0
          call_indirect (type 0)
          global.get 0
          local.set 1
          br_if 2 (;@1;)
        end
        local.get 1
        i64.extend_i32_u
        i64.const 72
        i64.add
        i32.wrap_i64
        local.get 1
        i64.load offset=24
        i64.store
        local.get 1
        i32.const 56
        i32.add
        local.tee 1
        global.set 0
        local.get 1
        i32.const 8
        i32.add
        local.tee 1
        global.set 0
        i32.const 0
        return
      end
      unreachable
    end
    i32.const 1)
  ;; And that’s the inner function.
  (func $main.fib.func1 (type 0) (param i32) (result i32)
    (local i32 i64 i64)
    global.get 0
    local.set 1
    block  ;; label = @1
      ;; Note this loop:
      loop  ;; label = @2
        block  ;; label = @3
          block  ;; label = @4
            block  ;; label = @5
              block  ;; label = @6
                block  ;; label = @7
                  block  ;; label = @8
                    block  ;; label = @9
                      local.get 0
                      br_table 0 (;@9;) 0 (;@9;) 1 (;@8;) 2 (;@7;) 3 (;@6;) 3 (;@6;) 3 (;@6;) 4 (;@5;) 5 (;@4;) 6 (;@3;)
                    end
                    local.get 1
                    global.get 2
                    i32.wrap_i64
                    i32.load offset=16
                    i32.le_u
                    if  ;; label = @9
                      local.get 1
                      i32.const 8
                      i32.sub
                      local.tee 1
                      global.set 0
                      local.get 1
                      i64.const 356712448
                      i64.store
                      i32.const 0
                      call $runtime.morestack
                      global.get 0
                      local.set 1
                      br_if 8 (;@1;)
                    end
                    local.get 1
                    i32.const 32
                    i32.sub
                    local.tee 1
                    global.set 0
                    global.get 1
                    local.tee 2
                    i32.wrap_i64
                    i64.load offset=8
                    local.set 2
                    local.get 1
                    i64.load offset=40
                    i64.eqz
                    if  ;; label = @9
                      i32.const 8
                      local.set 0
                      br 7 (;@2;)
                    end
                  end
                  local.get 1
                  i64.load offset=40
                  i64.const 1
                  i64.eq
                  i32.eqz
                  if  ;; label = @8
                    i32.const 4
                    local.set 0
                    ;; We jump to the beginning of the loop here.
                    ;; No recursive call in sight!
                    br 6 (;@2;)
                    ;; (If you’re wondering why I said that it's line 622806: that's because it is.
                    ;; The full file was too big to place it on GitHub, so I made some cuts)
                  end
                end
                local.get 1
                i64.extend_i32_u
                i64.const 64
                i64.add
                i32.wrap_i64
                local.get 1
                i64.load offset=56
                i64.store
                local.get 1
                i32.const 32
                i32.add
                local.tee 1
                global.set 0
                local.get 1
                i32.const 8
                i32.add
                local.tee 1
                global.set 0
                i32.const 0
                return
              end
              local.get 2
              i32.wrap_i64
              i64.load
              local.tee 2
              i64.eqz
              if  ;; label = @6
                local.get 1
                i32.const 8
                i32.sub
                local.tee 1
                global.set 0
                local.get 1
                i64.const 356712453
                i64.store
                i32.const 0
                call $runtime.sigpanic
                global.get 0
                local.set 1
                br_if 5 (;@1;)
              end
              local.get 2
              i32.wrap_i64
              i64.load
              local.set 3
              local.get 1
              local.get 1
              i64.load offset=40
              i64.const -1
              i64.add
              i64.store
              local.get 1
              i64.extend_i32_u
              i64.const 8
              i64.add
              i32.wrap_i64
              local.get 1
              i64.load offset=56
              i64.store
              local.get 1
              i64.extend_i32_u
              i64.const 16
              i64.add
              i32.wrap_i64
              local.get 1
              i64.load offset=56
              local.get 1
              i64.load offset=48
              i64.add
              i64.store
              local.get 2
              global.set 1
              local.get 3
              local.get 1
              i32.const 8
              i32.sub
              local.tee 1
              global.set 0
              local.get 1
              i64.const 356712455
              i64.store
              i32.wrap_i64
              i32.const 16
              i32.shr_u
              local.set 0
              i32.const 0
              local.get 0
              call_indirect (type 0)
              global.get 0
              local.set 1
              br_if 4 (;@1;)
            end
            local.get 1
            i64.extend_i32_u
            i64.const 64
            i64.add
            i32.wrap_i64
            local.get 1
            i64.extend_i32_u
            i64.const 24
            i64.add
            i32.wrap_i64
            i64.load
            i64.store
            local.get 1
            i32.const 32
            i32.add
            local.tee 1
            global.set 0
            local.get 1
            i32.const 8
            i32.add
            local.tee 1
            global.set 0
            i32.const 0
            return
          end
          local.get 1
          i64.extend_i32_u
          i64.const 64
          i64.add
          i32.wrap_i64
          local.get 1
          i64.load offset=48
          i64.store
          local.get 1
          i32.const 32
          i32.add
          local.tee 1
          global.set 0
          local.get 1
          i32.const 8
          i32.add
          local.tee 1
          global.set 0
          i32.const 0
          return
        end
      end
      unreachable
    end
    i32.const 1))
