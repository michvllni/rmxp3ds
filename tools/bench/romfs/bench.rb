# SPDX-License-Identifier: GPL-3.0-or-later
# M1 Ruby test and micro-benchmark for the 3DS (run by tools/bench, see main.c).
# Correctness checks raise on failure; the value of the last expression is the result text.
# Runs unchanged on a desktop Ruby for comparison:
#   ruby -r ./tools/bench/romfs/rgss_stubs tools/bench/romfs/bench.rb

lines = []
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
bench = lambda do |name, &blk|
  GC.start
  t0 = clock.call
  r = blk.call
  lines << format('bench %-22s %9.2f ms', name, (clock.call - t0) * 1000)
  r
end
check = ->(name, ok) { raise "check failed: #{name}" unless ok; lines << "check #{name} ok" }

lines << "ruby #{RUBY_VERSION} #{RUBY_PLATFORM}"

# --- correctness ---------------------------------------------------------------------------
check.call('arith', (1..10).sum == 55 && 2**40 == 1_099_511_627_776 && (7.0 / 2) == 3.5)
check.call('utf8', 'héllo wörld'.length == 11 && 'héllo'.encoding == Encoding::UTF_8)
check.call('sjis', "\x82\xa0".force_encoding('Shift_JIS').encode('UTF-8') == 'あ')
check.call('regexp', ('Map042' =~ /Map(\d+)/) == 0 && $1 == '042')
check.call('exception', begin; raise ArgumentError, 'x'; rescue ArgumentError => e; e.message == 'x'; end)
check.call('fiber', Fiber.new { Fiber.yield 1; 2 }.then { |f| [f.resume, f.resume] } == [1, 2])
check.call('enumerator_next', [1, 2, 3].each.then { |e| [e.next, e.next] } == [1, 2])
check.call('thread_value', Thread.new { 21 * 2 }.value == 42)
order = []
t = Thread.new { 2.times { |i| order << "t#{i}"; Thread.pass } }
2.times { |i| order << "m#{i}"; Thread.pass }
t.join
# Interleaving is not guaranteed by Ruby in general; on the 3DS it proves that Thread.pass
# really yields (newlib's sched_yield is a stub there, see runtime/3ds/ruby/README.md).
interleaved = order != %w[m0 m1 t0 t1]
check.call("thread_pass(#{order.join(',')})", order.sort == %w[m0 m1 t0 t1] && (interleaved || RUBY_PLATFORM !~ /eabi/))
q = Queue.new
consumer = Thread.new { Array.new(3) { q.pop } }
3.times { |i| q << i }
check.call('queue', consumer.value == [0, 1, 2])
mx = Mutex.new
cv = ConditionVariable.new
ready = false
waiter = Thread.new { mx.synchronize { cv.wait(mx) until ready; :woke } }
sleep 0.01
mx.synchronize { ready = true; cv.signal }
check.call('condvar', waiter.value == :woke)
require 'zlib'
blob = 'RMXP3DS' * 2000
check.call('zlib', Zlib::Inflate.inflate(Zlib::Deflate.deflate(blob)) == blob)

expected = RGSSStubs.digest(RGSSStubs.synthetic_map(40, 30, 60, 1))
fixture = ['sdmc:/rmxp3ds/test/Map001.rxdata', 'romfs:/Map001.rxdata'].find { |f| File.exist?(f) }
raise 'fixture Map001.rxdata not found' unless fixture
data = File.binread(fixture)
map = bench.call('marshal_load_fixture') { Marshal.load(data) }
check.call("marshal_fixture(#{fixture}, #{data.bytesize} B)", RGSSStubs.digest(map) == expected)
check.call('marshal_roundtrip', RGSSStubs.digest(Marshal.load(Marshal.dump(map))) == expected)

# --- micro-benchmarks ------------------------------------------------------------------------
bench.call('while_loop_1M') { i = 0; i += 1 while i < 1_000_000 }
def bench_add(a, b) = a + b
bench.call('method_call_300k') { i = 0; s = 0; while i < 300_000; s = bench_add(s, i); i += 1; end }
bench.call('block_yield_300k') { s = 0; 300_000.times { |i| s += i } }
bench.call('ivar_attr_200k') do
  o = RPG::EventCommand.new(0, 0, [])
  200_000.times { |i| o.code = i; o.indent = o.code }
end
bench.call('array_push_each_200k') { a = []; 200_000.times { |i| a << i }; s = 0; a.each { |v| s += v } }
bench.call('hash_set_get_100k') { h = {}; 100_000.times { |i| h[i] = i }; 100_000.times { |i| h[i] } }
bench.call('string_build_50k') { s = +''; 50_000.times { |i| s << "line #{i}\n" } }
bench.call('object_alloc_200k') { 200_000.times { RPG::EventCommand.new(1, 2, nil) } }
bench.call('table_rw_40x30x3_x10') do
  t = map.data
  10.times { 3.times { |z| 30.times { |y| 40.times { |x| t[x, y, z] = t[x, y, z] + 1 } } } }
end
bench.call('marshal_load_fixture_x10') { 10.times { Marshal.load(data) } }

stat = GC.stat
lines << format('gc count=%d heap_live_slots=%d heap_pages=%d total_allocated_objects=%d',
                stat[:count], stat[:heap_live_slots], stat[:heap_allocated_pages], stat[:total_allocated_objects])
lines.join("\n") + "\n"
