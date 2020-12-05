const std = @import("std");

const expect = std.testing.expect;


// would cause lose wake up event
// threadlocal var threadlocal_resetevent = std.AutoResetEvent{};


/// Condition variable
/// support wait(), timedWait(), signal(), signalAll()
pub const Condition = struct {
    ///this struct is on stack
    pub const Node = struct {
        status: i32=1,    //if status equal 1, Node is in queue or about to be in queue, orelse it has been removed from queue
        prev: ?*Node=null,
        next: ?*Node=null,
        reset: std.ResetEvent,
    };
    
    
    head: ?*Node=null,
    tail: ?*Node=null,
    mutex: ?*std.Mutex,
    
    const Self = @This();

    /// Initializes a new condition variable.
    pub fn init(mutex: *std.Mutex) Self {
        return Self {.head = null, .tail=null, .mutex=mutex};
    }

    fn remove_head(self: *Self) *Node{
        var node: *Node = self.head.?;
        self.head = node.next;
        if(node.next == null){
            expect(self.tail == node);
            self.tail = null;
        } else {
            node.next.?.prev = null;
        }
        return node;
    }

    fn remove_waiter(self: *Self, node: *Node) void {
        expect(self.head != null);
        if (self.head.? == node){
            const n = self.remove_head();
            expect(n == node);
        } else {
            const prev = node.prev.?;
            prev.next = node.next;
            if(node.next != null){
                node.next.?.prev = prev;
            } else {
                expect(self.tail == node);
                self.tail = prev;
            }
        }
    }
    
    fn add_waiter(self: *Self, node: *Node) void {
        if(self.head == null){
            expect(self.tail == null);
            self.head = node;
            self.tail = node;
        } else {
            expect(self.tail != null);
            expect(self.tail != node);
            node.prev = self.tail;
            self.tail.?.next = node;
            self.tail = node;
        }        
    }

    // wait until signaled. The thread who call signal()/signalAll() remove node from queue
    pub fn wait(self: *Self) void {
        var node = Node{.status = 1, .reset = std.ResetEvent.init()};
        defer node.reset.deinit();
        self.add_waiter(&node);
        var lock = std.Mutex.Held{.mutex = self.mutex.?};
        lock.release();
        //while(@atomicLoad(i32, &node.status, .SeqCst) != 0) {
            node.reset.wait();
            var val = @atomicLoad(i32, &node.status, .SeqCst);
            if(val != 0){
                std.debug.print("waked but status not 0 : {} {} {*} {*}\n", .{std.Thread.getCurrentId(),val, node.next, node.prev});
            }
        //}
        lock = self.mutex.?.acquire();
    }

    /// wait until signaled or timeout, if signaled, node has already been dequeue, orelse its still in queue,
    /// and remove node ourselves
    pub fn timedWait(self: *Self, timeout: u64) i64 {
        var node = Node{.status = 1, .reset = std.ResetEvent.init()};
        defer node.reset.deinit();
        self.add_waiter(&node);

        var lock = std.Mutex.Held{.mutex = self.mutex.?};
        lock.release();

        const deadline = std.time.nanoTimestamp() + @intCast(i128, timeout);
        const ret = node.reset.timedWait(timeout);
        const remain = deadline - std.time.nanoTimestamp();
        if(@atomicLoad(i32, &node.status, .SeqCst) == 0) {
            lock = self.mutex.?.acquire();
            return @intCast(i64, remain);
        } else {
            lock = self.mutex.?.acquire();
            if (node.status != 0)
                self.remove_waiter(&node);
                
            if(ret) |_| {
                expect(false); // unexpected waken up
            } else |timeout_err| {}
            return @intCast(i64, remain);
        }
    }


    pub fn signal(self: *Self) void {
        if(self.head == null)
            return;
            
        var node: *Node = self.remove_head();
        expect(node.prev == null);
        expect(node.next == self.head);

        node.next = null;
        node.prev = null;
        node.status = 0;
        node.reset.set();
    }
    
    pub fn signalAll(self: *Self) void {
        var node: ?*Node = self.head;
        self.head = null;
        self.tail = null;
        
        while(node != null) {
            var cur = node.?;
            node = cur.next;
            
            cur.next = null;
            cur.prev = null;
            cur.status = 0;
            cur.reset.set();
        }
    }

};

