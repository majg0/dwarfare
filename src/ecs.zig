const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Vec3 = @import("math.zig").Vec3;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const page_size = std.mem.page_size;
const component_count_max = 8;
const entity_count_max = 100;
const storage_count_max = 8;

const Component = struct {
    size: usize,
    alignment: usize,

    fn from_type(comptime T: type) Component {
        return Component{
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
        };
    }
};

const Archetype = struct {
    const BitSet = std.bit_set.IntegerBitSet(component_count_max);

    bit_set: BitSet,

    fn init() Archetype {
        return Archetype{ .bit_set = BitSet.initEmpty() };
    }

    fn with(self: Archetype, component_index: usize) Archetype {
        var bit_set = self.bit_set;
        bit_set.set(component_index);
        return Archetype{ .bit_set = bit_set };
    }

    fn has(self: *const Archetype, component_index: usize) bool {
        return self.bit_set.isSet(component_index);
    }

    fn storageIndex(self: Archetype, world: *World) u32 {
        for (world.storages.list.items, 0..) |storage, index| {
            if (storage.archetype.bit_set.eql(self.bit_set)) {
                return @intCast(index);
            }
        }
        unreachable;
    }
};

fn Registry(comptime T: type) type {
    return struct {
        const Self = @This();

        list: std.ArrayListUnmanaged(T),

        fn init(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            return Self{
                .list = try std.ArrayListUnmanaged(T).initCapacity(
                    allocator,
                    capacity,
                ),
            };
        }

        fn deinit(self: *Self, allocator: Allocator) void {
            self.list.deinit(allocator);
        }

        fn register(self: *Self, item: T) usize {
            const id = self.list.items.len;
            self.list.appendAssumeCapacity(item);
            return id;
        }
    };
}

const Filter = struct {
    mask_include: Archetype,
    mask_exclude: Archetype,

    pub fn init() Filter {
        return Filter{
            .mask_include = Archetype.init(),
            .mask_exclude = Archetype.init(),
        };
    }

    fn with(self: Filter, component_index: usize) Filter {
        return Filter{
            .mask_include = self.mask_include.with(component_index),
            .mask_exclude = self.mask_exclude,
        };
    }

    fn without(self: Filter, component_index: usize) Filter {
        return Filter{
            .mask_include = self.mask_include,
            .mask_exclude = self.mask_exclude.with(component_index),
        };
    }

    pub fn match(self: *const Filter, archetype: Archetype) bool {
        return self.mask_include.bit_set.subsetOf(archetype.bit_set) and
            self.mask_exclude.bit_set.intersectWith(archetype.bit_set).count() == 0;
    }
};

const Query = struct {
    filter: Filter,
    storage_index: usize,
    world: *const World,

    fn init(filter: Filter, world: *const World) Query {
        return Query{
            .world = world,
            .filter = filter,
            .storage_index = 0,
        };
    }

    fn next(self: *Query) ?*Storage {
        const items = self.world.storages.list.items;
        while (self.storage_index < items.len) {
            var storage = items[self.storage_index];
            self.storage_index += 1;
            if (self.filter.match(storage.archetype)) {
                return &storage;
            }
        }
        return null;
    }
};

const Entity = packed struct {
    index: u32,
    generation: u32,

    fn eq(lhs: Entity, rhs: Entity) bool {
        return std.mem.eql(Entity, &lhs, &rhs);
        // return lhs.index == rhs.index and lhs.generation == rhs.generation;
    }

    fn pointer(self: Entity, world: *World) *const Pointer {
        return world.entities.pointer(self);
    }
};

const Pointer = struct {
    storage_index: u32,
    row: u32,

    fn storage(self: Pointer, world: *World) *Storage {
        return &world.storages.list.items[self.storage_index];
    }

    fn invalidate(self: *Pointer) void {
        self.storage_index = storage_count_max;
    }

    fn valid(self: Pointer) bool {
        return self.storage_index < storage_count_max;
    }

    fn invalid(self: Pointer) bool {
        return self.storage_index >= storage_count_max;
    }
};

const Entities = struct {
    index_next: u32,
    free_count: u32,
    generations: []u32,
    free_list: []u32,
    pointers: []Pointer,

    fn init(allocator: Allocator) Allocator.Error!Entities {
        const generations = try allocator.alignedAlloc(u32, std.mem.page_size, entity_count_max);
        for (generations) |*generation| {
            generation.* = 0;
        }
        return Entities{
            .index_next = 0,
            .free_count = 0,
            .generations = generations,
            .free_list = try allocator.alignedAlloc(u32, std.mem.page_size, entity_count_max),
            .pointers = try allocator.alignedAlloc(Pointer, std.mem.page_size, entity_count_max),
        };
    }

    fn deinit(self: *Entities, allocator: Allocator) void {
        allocator.free(self.generations);
        allocator.free(self.free_list);
        allocator.free(self.pointers);
    }

    fn create(self: *Entities) Entity {
        if (self.free_count == 0) {
            assert(self.index_next < entity_count_max);
            const index = self.index_next;
            self.pointers[index].invalidate();
            const entity = Entity{ .index = index, .generation = self.generations[index] };
            self.index_next += 1;
            return entity;
        } else {
            self.free_count -= 1;
            const index = self.free_list[self.free_count];
            self.pointers[index].invalidate();
            return Entity{ .index = index, .generation = self.generations[index] };
        }
    }

    fn destroy(self: *Entities, entity: Entity) void {
        self.free_list[self.free_count] = entity.index;
        self.free_count += 1;
        // NOTE: ensures we can check liveness via `is_alive`
        self.generations[entity.index] +%= 1;
    }

    fn alive(self: *const Entities, entity: Entity) bool {
        return entity.generation == self.generations[entity.index];
    }

    fn dead(self: *const Entities, entity: Entity) bool {
        return entity.generation != self.generations[entity.index];
    }

    fn pointer(self: *const Entities, entity: Entity) *Pointer {
        assert(self.alive(entity));
        return &self.pointers[entity.index];
    }
};

test "entities" {
    const expectEqual = std.testing.expectEqual;
    const expect = std.testing.expect;

    const allocator = std.testing.allocator;
    var entities = try Entities.init(allocator);
    defer entities.deinit(allocator);

    const e0 = entities.create();
    try expectEqual(0, e0.index);
    try expectEqual(0, e0.generation);
    try expect(entities.alive(e0));
    const e1 = entities.create();
    try expectEqual(1, e1.index);
    try expectEqual(0, e1.generation);
    try expect(entities.alive(e1));
    const e2 = entities.create();
    try expectEqual(2, e2.index);
    try expectEqual(0, e2.generation);
    try expect(entities.alive(e2));

    entities.destroy(e1);
    try expect(entities.dead(e1));
    const e3 = entities.create();
    try expectEqual(1, e3.index);
    try expectEqual(1, e3.generation);
    try expect(entities.alive(e3));
    try expect(entities.dead(e1));
}

const World = struct {
    components: Registry(Component),
    storages: Registry(Storage),
    entities: Entities,

    fn init(allocator: Allocator) Allocator.Error!World {
        return World{
            .components = try Registry(Component).init(allocator, component_count_max),
            .storages = try Registry(Storage).init(allocator, storage_count_max),
            .entities = try Entities.init(allocator),
        };
    }

    fn deinit(self: *World, allocator: Allocator) void {
        self.components.deinit(allocator);
        self.storages.deinit(allocator);
    }

    fn query(self: *World, filter: Filter) Query {
        return Query.init(filter, self);
    }

    fn create(self: *World, archetype: Archetype) Entity {
        const entity = self.entities.create();
        assert(self.entities.pointer(entity).invalid());
        self.move(entity, archetype);
        assert(self.entities.pointer(entity).valid());
        return entity;
    }

    fn destroy(self: *World, entity: Entity) void {
        const ptr = self.entities.pointer(entity);
        ptr.storage(self).swapRemove(ptr.row);
        self.entities.destroy(entity);
    }

    fn storage(self: *World, storage_index: u32) *Storage {
        return &self.storages.list.items[storage_index];
    }

    fn move(self: *World, entity: Entity, archetype: Archetype) void {
        assert(self.entities.alive(entity));
        const ptr = self.entities.pointer(entity);
        const storage_index_target = archetype.storageIndex(self);
        assert(storage_index_target < self.storages.list.items.len);

        if (storage_index_target == ptr.storage_index) {
            return;
        }
        if (ptr.valid()) {
            self.storage(ptr.storage_index).swapRemove(ptr.row);
            // TODO: move what can be moved
            unreachable;
        }
        ptr.storage_index = storage_index_target;
        ptr.row = self.storage(storage_index_target).insert();
    }

    fn get(self: *World, comptime T: type, entity: Entity, component_index: usize) *T {
        const ptr = entity.pointer(self);
        const table = ptr.storage(self);
        assert(table.archetype.has(component_index));
        return table.cell(T, ptr.row, component_index);
    }

    fn createStorage(self: *World, allocator: Allocator, archetype: Archetype) Allocator.Error!*Storage {
        {
            // assert monotonically decreasing alignment
            var iter = archetype.bit_set.iterator(.{});
            var prev_alignment = self.components.list.items[iter.next() orelse unreachable].alignment;
            while (iter.next()) |component_index| {
                const component = self.components.list.items[component_index];
                assert(prev_alignment >= component.alignment);
                prev_alignment = component.alignment;
            }
        }

        const entities_per_page: usize = blk: {
            var size_total: usize = 0;
            var iter = archetype.bit_set.iterator(.{});
            while (iter.next()) |component_index| {
                const component = self.components.list.items[component_index];
                // NOTE: to fit more data, let's be explicit about padding
                assert(component.size >= component.alignment);
                size_total += component.size;
            }

            break :blk page_size / size_total;
        };

        var prev_offset: usize = 0;
        const columns = try allocator.alloc(Storage.Column, archetype.bit_set.count());

        {
            var iter = archetype.bit_set.iterator(.{});
            for (columns) |*column| {
                const elem = iter.next();
                assert(elem != null);
                const component_index = elem.?;
                const component = self.components.list.items[component_index];
                // NOTE: you may affect this by reordering the registration of components
                assert(component.size >= component.alignment);
                prev_offset = std.mem.alignForward(usize, prev_offset, component.alignment);
                column.offset = prev_offset;
                column.size = component.size;
                column.component_index = component_index;
                prev_offset += component.size * entities_per_page;
            }
            assert(iter.next() == null);
        }

        const index = self.storages.register(Storage{
            .world = self,
            .archetype = archetype,
            .columns = columns,
            .pages = undefined,
            .entities_per_page = entities_per_page,
            .count_used = 0,
        });

        var result = &self.storages.list.items[index];
        try result.init(allocator);

        return result;
    }
};

const Storage = struct {
    const Page = struct {
        storage: *Storage,
        data: []align(page_size) u8,
        entity_count: usize,

        pub fn slice(self: *const Page, component_index: usize, comptime T: type) []T {
            const column = self.storage.columnOf(component_index);
            const begin = column.offset;
            const end = column.offset + column.size * self.entity_count;
            return @alignCast(std.mem.bytesAsSlice(T, self.data[begin..end]));
        }

        pub fn get(self: *const Page, column: Column, index: usize) []u8 {
            const begin = column.offset + index * column.size;
            const end = column.offset + index * column.size + column.size;
            return self.data[begin..end];
        }
    };

    const Column = struct {
        component_index: usize,
        offset: usize,
        size: usize,
    };

    world: *World,
    archetype: Archetype,
    columns: []const Column,
    pages: []Page,
    entities_per_page: usize,
    count_used: u32,

    fn columnOf(self: *const Storage, component_index: usize) Column {
        // NOTE: this is a bit of magic but it makes sense if you think about it :)
        //
        // Given:
        // component_index = 2
        //                    this is the index bit
        //                    v
        // archetype       = 0110
        //                     ^^
        //                     these are the components with smaller indices
        //
        // The number of 1 bits to the right of the index coincides with the offset index.
        // A special CPU instruction known as the "population count" counts set bits.
        //
        // Thus we first produce a mask 0011; this is (1 << component_index) - 1:
        const mask = std.math.shl(Archetype.BitSet.MaskInt, 1, component_index) - 1;

        // Then we simply mask off and count the bits
        const index = @popCount(self.archetype.bit_set.mask & mask);
        const column = self.columns[index];
        assert(column.component_index == component_index);
        return column;
    }

    fn insert(self: *Storage) u32 {
        assert(self.count_used < entity_count_max);
        const row = self.count_used;
        self.count_used += 1;
        return row;
    }

    fn cell(self: *const Storage, comptime T: type, row: usize, component_index: usize) *T {
        return @alignCast(@ptrCast(
            self.pages[row / self.entities_per_page].get(
                self.columnOf(component_index),
                row % self.entities_per_page,
            ),
        ));
    }

    fn swapRemove(self: *Storage, row: usize) void {
        assert(row < self.count_used);
        self.count_used -= 1;

        const page_last = self.pages[self.pages.len - 1];
        const index_last = page_last.entity_count - 1;
        const page_stale = self.pages[row / self.entities_per_page];
        const index_stale = row % self.entities_per_page;

        for (self.columns) |column| {
            const last = page_last.get(column, index_last);
            const stale = page_stale.get(column, index_stale);
            @memcpy(stale, last);
        }
    }

    fn init(self: *Storage, allocator: Allocator) Allocator.Error!void {
        var entity_count_remaining: usize = entity_count_max;
        const page_count = (entity_count_max - 1) / self.entities_per_page + 1;
        self.pages = try allocator.alloc(Storage.Page, page_count);
        for (self.pages) |*page| {
            const count = @min(entity_count_remaining, self.entities_per_page);
            entity_count_remaining -= count;
            page.* = Storage.Page{
                .entity_count = count,
                .storage = self,
                .data = try allocator.alignedAlloc(u8, page_size, page_size),
            };
        }
        assert(entity_count_remaining == 0);
    }

    fn deinit(self: *Storage, allocator: Allocator) void {
        for (self.pages) |page| {
            allocator.free(page.data);
        }
    }
};

const Player = struct {
    name: []const u8,
    location: Vec3,
    velocity: Vec3,
    health: u8,
};

const Cat = struct {
    name: []const u8,
    location: Vec3,
};

test "ecs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var world = try World.init(allocator);
    defer world.deinit(allocator);

    // register components
    const component_player = world.components.register(Component.from_type(Player));
    const component_cat = world.components.register(Component.from_type(Cat));

    // create archetypes
    const archetype_player = Archetype.init().with(component_player);
    const archetype_cat_player = Archetype.init().with(component_cat).with(component_player);

    // create storages
    const storage_player = try world.createStorage(allocator, archetype_player);
    const storage_cat_player = try world.createStorage(allocator, archetype_cat_player);

    // correct storage sizes
    {
        var entity_count: usize = 0;
        for (storage_cat_player.pages) |*page| {
            const cats = page.slice(component_cat, Cat);
            const players = page.slice(component_player, Player);
            assert(cats.len == players.len);
            entity_count += cats.len;
        }
        assert(entity_count == entity_count_max);
    }
    {
        var entity_count: usize = 0;
        for (storage_player.pages) |*page| {
            const players = page.slice(component_player, Player);
            entity_count += players.len;
        }
        assert(entity_count == entity_count_max);
    }

    // query inclusion
    {
        var query = world.query(Filter.init().with(component_player));
        var count: u8 = 0;
        while (query.next() != null) {
            count += 1;
        }
        assert(count == 2);
    }

    // query exclusion
    {
        var query = world.query(Filter.init().with(component_player).without(component_cat));
        var count: u8 = 0;
        while (query.next() != null) {
            count += 1;
        }
        assert(count == 1);
    }

    // foo
    {
        const t = std.testing;
        try t.expectEqual(0, storage_player.count_used);

        const e1 = world.create(archetype_player);
        try t.expect(world.entities.alive(e1));
        try t.expectEqual(1, storage_player.count_used);

        const e2 = world.create(archetype_player);
        try t.expect(world.entities.alive(e2));
        try t.expectEqual(2, storage_player.count_used);

        const p1 = world.get(Player, e1, component_player);
        const p2 = world.get(Player, e2, component_player);

        p1.health = 3;

        const size = @sizeOf(Player);
        {
            const slice = storage_player.pages[0].data[0..size];
            const p = @as(*Player, @ptrCast(slice.ptr));
            try t.expectEqual(@sizeOf(Player), slice.len);
            try t.expectEqual(p1, p);
        }
        {
            const slice = storage_player.pages[0].data[size .. size * 2];
            const p = @as(*Player, @ptrCast(slice.ptr));
            try t.expectEqual(@sizeOf(Player), slice.len);
            try t.expectEqual(p2, p);
        }
        // NOTE: destroy without mirroring order to test swap remove

        try t.expectEqual(0, e1.pointer(&world).row);
        try t.expectEqual(1, e2.pointer(&world).row);
        world.destroy(e1);
        try t.expect(world.entities.dead(e1));
        try t.expectEqual(1, storage_player.count_used);
        // e1 was not last so it should've swapped with e2; ensure e2's pointer was updated
        try t.expectEqual(0, e2.pointer(&world).row);

        world.destroy(e2);
        try t.expect(world.entities.dead(e2));
        try t.expectEqual(0, storage_player.count_used);
    }
}
