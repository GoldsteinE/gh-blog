;; This file was _much_ larger originally, I cut a lot of stuff to make it manageable.

;; That's our outer function:
main.fib:
cmp    0x10(%r14),%rsp
jbe    48301b <main.fib+0x5b>
sub    $0x38,%rsp
mov    %rbp,0x30(%rsp)
lea    0x30(%rsp),%rbp
movq   $0x0,0x18(%rsp)
movups %xmm15,0x20(%rsp)
lea    0x56(%rip),%rsi        # 483040 <main.fib.func1>
mov    %rsi,0x20(%rsp)
lea    0x18(%rsp),%rsi
mov    %rsi,0x28(%rsp)
lea    0x20(%rsp),%rdx
mov    %rdx,0x18(%rsp)
mov    0x20(%rsp),%rsi
xor    %ebx,%ebx
mov    $0x1,%ecx
;; And here it calls the inner function.
call   *%rsi
;; Interestingly, it's a dynamic call for no obvious reason.
mov    0x30(%rsp),%rbp
add    $0x38,%rsp
ret
mov    %rax,0x8(%rsp)
call   45bd00 <runtime.morestack_noctxt.abi0>
mov    0x8(%rsp),%rax
jmp    482fc0 <main.fib>

;; That's our inner function
main.fib.func1:
cmp    0x10(%r14),%rsp
jbe    48309f <main.fib.func1+0x5f>
sub    $0x20,%rsp
mov    %rbp,0x18(%rsp)
lea    0x18(%rsp),%rbp
mov    0x8(%rdx),%rsi
test   %rax,%rax
je     483092 <main.fib.func1+0x52>
nopl   (%rax)
cmp    $0x1,%rax
jne    483073 <main.fib.func1+0x33>
mov    %rcx,%rax
mov    0x18(%rsp),%rbp
add    $0x20,%rsp
ret
mov    (%rsi),%rdx
mov    (%rdx),%rsi
dec    %rax
lea    (%rcx,%rbx,1),%rdi
mov    %rcx,%rbx
mov    %rdi,%rcx
;; And this call is clearly a recursive call
;; (I double-checked it in debugger to be sure)
call   *%rsi
;; That's a dynamic call again. Why, Go? Why?
mov    0x18(%rsp),%rbp
add    $0x20,%rsp
ret
mov    %rbx,%rax
mov    0x18(%rsp),%rbp
add    $0x20,%rsp
ret
mov    %rax,0x8(%rsp)
mov    %rbx,0x10(%rsp)
mov    %rcx,0x18(%rsp)
;; Fun allocation stuff: that's what makes binaries so large.
call   45bc60 <runtime.morestack.abi0>
mov    0x8(%rsp),%rax
mov    0x10(%rsp),%rbx
mov    0x18(%rsp),%rcx
jmp    483040 <main.fib.func1>
