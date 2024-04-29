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

    fn forStorage(self: Archetype) Archetype {
        var bit_set = self.bit_set;
        bit_set.set(World.component_index_entity);
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

    fn component_count(self: Archetype) usize {
        return self.bit_set.count();
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
    rows_iterator: ?RowsIterator,

    fn init(filter: Filter, world: *const World) Query {
        return Query{
            .world = world,
            .filter = filter,
            .storage_index = 0,
            .rows_iterator = null,
        };
    }

    fn next(self: *Query) ?Rows {
        if (self.rows_iterator == null) {
            const storages = self.world.storages.list.items;
            while (self.storage_index < storages.len) {
                const storage_candidate = &storages[self.storage_index];
                self.storage_index += 1;
                if (self.filter.match(storage_candidate.archetype)) {
                    self.rows_iterator = storage_candidate.rowsIterator();
                    break;
                }
            } else {
                return null;
            }
        }

        assert(self.rows_iterator != null);

        var rows_iterator = &self.rows_iterator.?;

        if (rows_iterator.next()) |rows| {
            if (rows_iterator.last_page()) {
                self.rows_iterator = null;
            }
            return rows;
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

    fn getPointer(self: Entity, world: *const World) *Pointer {
        return world.entities.getPointer(self);
    }
};

const Pointer = struct {
    storage_index: u32,
    row_index: u32,

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

    fn getPointer(self: *const Entities, entity: Entity) *Pointer {
        assert(self.alive(entity));
        return &self.pointers[entity.index];
    }
};

test "entity allocation" {
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
    const component_index_entity = 0;

    components: Registry(Component),
    storages: Registry(Storage),
    entities: Entities,

    fn init(allocator: Allocator) Allocator.Error!World {
        var components = try Registry(Component).init(allocator, component_count_max);
        assert(component_index_entity == components.register(Component.from_type(Entity)));
        return World{
            .components = components,
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
        assert(self.entities.getPointer(entity).invalid());
        self.move(entity, archetype);
        assert(self.entities.getPointer(entity).valid());
        return entity;
    }

    fn destroy(self: *World, entity: Entity) void {
        const ptr = entity.getPointer(self);
        ptr.storage(self).swapRemove(ptr.row_index);
        self.entities.destroy(entity);
    }

    fn getComponent(self: *World, component_index: usize) *const Component {
        return &self.components.list.items[component_index];
    }

    fn getStorage(self: *World, storage_index: u32) *Storage {
        return &self.storages.list.items[storage_index];
    }

    fn move(self: *World, entity: Entity, archetype: Archetype) void {
        assert(self.entities.alive(entity));
        const ptr = self.entities.getPointer(entity);
        const storage_index_target = archetype.storageIndex(self);
        assert(storage_index_target < self.storages.list.items.len);

        if (storage_index_target == ptr.storage_index) {
            return;
        }
        if (ptr.valid()) {
            self.getStorage(ptr.storage_index).swapRemove(ptr.row_index);
            // TODO: move what can be moved
            unreachable;
        }
        ptr.storage_index = storage_index_target;
        ptr.row_index = self.getStorage(storage_index_target).insert(entity);
    }

    fn get(self: *World, comptime T: type, entity: Entity, component_index: usize) *T {
        const ptr = entity.getPointer(self);
        const table = ptr.storage(self);
        assert(table.archetype.has(component_index));
        return table.get(T, ptr.row_index, component_index);
    }

    fn registerComponent(self: *World, comptime T: type) usize {
        return self.components.register(Component.from_type(T));
    }

    fn createStorage(self: *World, allocator: Allocator, archetype: Archetype) Allocator.Error!*Storage {
        assert(archetype.has(component_index_entity));

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
        const component_count = archetype.component_count();
        const column_infos = try allocator.alloc(
            Storage.ColumnInfo,
            component_count,
        );

        {
            var iter = archetype.bit_set.iterator(.{});
            for (column_infos) |*column_info| {
                const elem = iter.next();
                assert(elem != null);
                const component_index = elem.?;
                const component = self.getComponent(component_index);
                // NOTE: you may affect this by reordering the registration of components
                assert(component.size >= component.alignment);
                prev_offset = std.mem.alignForward(usize, prev_offset, component.alignment);
                column_info.offset = prev_offset;
                column_info.size = component.size;
                column_info.component_index = component_index;
                prev_offset += component.size * entities_per_page;
            }
            assert(iter.next() == null);
        }

        const index = self.storages.register(Storage{
            .world = self,
            .archetype = archetype,
            .column_infos = column_infos,
            .pages = undefined,
            .entities_per_page = entities_per_page,
            .count_used = 0,
        });

        var result = &self.storages.list.items[index];
        try result.init(allocator);

        return result;
    }
};

const Rows = struct {
    page: *Storage.Page,
    entity_count: usize,

    fn get(self: *const Rows, comptime T: type, component_index: usize) []T {
        return self.page.slice(T, component_index, self.entity_count);
    }
};

const RowsIterator = struct {
    storage: *Storage,
    page_count: usize,
    page_index: usize,

    fn init(storage: *Storage) RowsIterator {
        return RowsIterator{
            .storage = storage,
            .page_count = std.math.divCeil(
                usize,
                storage.count_used,
                storage.entities_per_page,
            ) catch unreachable,
            .page_index = 0,
        };
    }

    fn last_page(self: *const RowsIterator) bool {
        return self.page_index == self.page_count;
    }

    fn next(self: *RowsIterator) ?Rows {
        if (self.last_page()) {
            return null;
        }
        const page = &self.storage.pages[self.page_index];
        self.page_index += 1;
        if (self.last_page()) {
            const entity_count = self.storage.count_used % self.storage.entities_per_page;
            return Rows{ .page = page, .entity_count = entity_count };
        }
        return Rows{ .page = page, .entity_count = page.entity_count };
    }
};

const Storage = struct {
    const Page = struct {
        storage: *Storage,
        data: []align(page_size) u8,
        entity_count: usize,

        fn slice(self: *const Page, comptime T: type, component_index: usize, entity_count: usize) []T {
            assert(entity_count <= self.entity_count);
            const column_info = self.storage.columnInfo(component_index);
            const begin = column_info.offset;
            const end = column_info.offset + column_info.size * entity_count;
            return @alignCast(std.mem.bytesAsSlice(T, self.data[begin..end]));
        }

        pub fn sliceFull(self: *const Page, comptime T: type, component_index: usize) []T {
            const column_info = self.storage.columnInfo(component_index);
            const begin = column_info.offset;
            const end = column_info.offset + column_info.size * self.entity_count;
            return @alignCast(std.mem.bytesAsSlice(T, self.data[begin..end]));
        }

        pub fn get(self: *const Page, column_info: ColumnInfo, index: usize) []u8 {
            const begin = column_info.offset + index * column_info.size;
            const end = column_info.offset + index * column_info.size + column_info.size;
            return self.data[begin..end];
        }
    };

    const ColumnInfo = struct {
        component_index: usize,
        offset: usize,
        size: usize,
    };

    world: *World,
    archetype: Archetype,
    column_infos: []const ColumnInfo,
    pages: []Page,
    entities_per_page: usize,
    count_used: u32,

    fn rowsIterator(self: *Storage) RowsIterator {
        return RowsIterator.init(self);
    }

    fn columnInfo(self: *const Storage, component_index: usize) ColumnInfo {
        // NOTE: this is a bit of magic but it makes sense if you think about it :)
        //
        // Given:
        // component_index = 3
        //                    this is the index bit
        //                    v
        // archetype       = 01101
        //                     ^^^
        //                     these are the components with smaller indices
        //
        // The number of 1 bits to the right of the index coincides with the offset index.
        // A special CPU instruction known as the "population count" counts set bits.
        //
        // Thus we first produce a mask 0011; this is (1 << component_index) - 1:
        const mask = std.math.shl(Archetype.BitSet.MaskInt, 1, component_index) - 1;

        // Then we simply mask off and count the bits
        const index = @popCount(self.archetype.bit_set.mask & mask);
        const column_info = self.column_infos[index];
        assert(column_info.component_index == component_index);
        return column_info;
    }

    fn insert(self: *Storage, entity: Entity) u32 {
        assert(self.count_used < entity_count_max);
        const row_index = self.count_used;
        self.get(Entity, row_index, World.component_index_entity).* = entity;
        self.count_used += 1;
        return row_index;
    }

    fn get(self: *const Storage, comptime T: type, row_index: usize, component_index: usize) *T {
        return @alignCast(@ptrCast(
            self.pages[row_index / self.entities_per_page].get(
                self.columnInfo(component_index),
                row_index % self.entities_per_page,
            ),
        ));
    }

    fn swapRemove(self: *Storage, row_index: u32) void {
        assert(row_index < self.count_used);
        self.count_used -= 1;

        const swap_row_index = self.count_used;
        if (swap_row_index == row_index) {
            return;
        }

        const page_last = self.pages[row_index / self.entities_per_page];
        const subindex_last = swap_row_index % self.entities_per_page;
        const page_stale = self.pages[row_index / self.entities_per_page];
        const subindex_stale = row_index % self.entities_per_page;

        for (self.column_infos) |column_info| {
            const last = page_last.get(column_info, subindex_last);
            const stale = page_stale.get(column_info, subindex_stale);
            @memcpy(stale, last);
        }

        // NOTE: there's a new entity in the old position; update that entity's pointer.
        self.getEntity(row_index).getPointer(self.world).row_index = row_index;
    }

    fn getEntity(self: *const Storage, row_index: usize) *Entity {
        return self.get(Entity, row_index, World.component_index_entity);
    }

    fn init(self: *Storage, allocator: Allocator) Allocator.Error!void {
        var entity_count_remaining: usize = entity_count_max;
        const page_count = std.math.divCeil(
            usize,
            entity_count_max,
            self.entities_per_page,
        ) catch unreachable;
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

test "ecs" {
    const t = std.testing;

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

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var world = try World.init(allocator);
    defer world.deinit(allocator);

    // register components
    const component_player = world.registerComponent(Player);
    const component_cat = world.registerComponent(Cat);

    // create archetypes
    const archetype_player = Archetype.init().with(component_player).forStorage();
    const archetype_cat_player = Archetype.init().with(component_cat).with(component_player).forStorage();

    // create storages
    const storage_player = try world.createStorage(allocator, archetype_player);
    const storage_cat_player = try world.createStorage(allocator, archetype_cat_player);

    // correct storage sizes
    {
        var entity_count: usize = 0;
        for (storage_cat_player.pages) |*page| {
            const entities = page.sliceFull(Entity, World.component_index_entity);
            const cats = page.sliceFull(Cat, component_cat);
            const players = page.sliceFull(Player, component_player);
            try t.expectEqual(cats.len, players.len);
            try t.expectEqual(entities.len, cats.len);
            entity_count += entities.len;
        }
        try t.expectEqual(entity_count_max, entity_count);
    }
    {
        var entity_count: usize = 0;
        for (storage_player.pages) |*page| {
            const players = page.sliceFull(Player, component_player);
            entity_count += players.len;
        }
        try t.expectEqual(entity_count_max, entity_count);
    }

    // entities
    {
        try t.expectEqual(0, storage_player.count_used);

        const e1 = world.create(archetype_player);
        try t.expect(world.entities.alive(e1));
        try t.expectEqual(1, storage_player.count_used);
        try t.expectEqual(0, e1.getPointer(&world).row_index);

        const e2 = world.create(archetype_player);
        try t.expect(world.entities.alive(e2));
        try t.expectEqual(2, storage_player.count_used);
        try t.expectEqual(1, e2.getPointer(&world).row_index);

        const e3 = world.create(archetype_cat_player);
        try t.expect(world.entities.alive(e2));
        try t.expectEqual(2, storage_player.count_used);
        try t.expectEqual(1, e2.getPointer(&world).row_index);

        const p1 = world.get(Player, e1, component_player);
        const p2 = world.get(Player, e2, component_player);
        const p3 = world.get(Player, e3, component_player);

        p1.health = 3;
        p2.health = 5;
        p3.health = 7;

        {
            var query = world.query(Filter.init()
                .with(component_player)
                .without(component_cat));
            var sum: u32 = 0;
            while (query.next()) |rows| {
                const entities = rows.get(Entity, World.component_index_entity);
                const players = rows.get(Player, component_player);
                for (entities, players) |entity, player| {
                    sum += (entity.index + 1) * player.health;
                }
            }
            try t.expectEqual((0 + 1) * 3 + (1 + 1) * 5, sum);
        }

        const e_stored = storage_player.get(Entity, 1, World.component_index_entity);
        try t.expectEqual(e2, e_stored.*);

        try t.expectEqual(0, e1.getPointer(&world).row_index);
        try t.expectEqual(1, e2.getPointer(&world).row_index);
        // NOTE: destroy without mirroring order to test swap remove
        world.destroy(e1);
        try t.expect(world.entities.dead(e1));
        try t.expectEqual(1, storage_player.count_used);
        // e1 was not last so it should've swapped with e2; ensure e2's pointer was updated
        try t.expectEqual(0, e2.getPointer(&world).row_index);

        world.destroy(e2);
        try t.expect(world.entities.dead(e2));
        try t.expectEqual(0, storage_player.count_used);
    }
}
