# Condition.zig
condition variable for zig lang

# how to use
```
const Condition = @import("./Condition.zig").Condition;
....
one thread:
mutex = std.Mutex{};
cond = Condition.init(&mutex);

const lock = mutex.acquire();
cond.wait();

...
another thread:
const lock = mutex.acquire()
cond.signal();
lock.release();
