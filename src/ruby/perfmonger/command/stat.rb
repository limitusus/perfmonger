
require 'optparse'
require 'json'

module PerfMonger
module Command

class StatCommand < BaseCommand
  register_command 'stat'

  def initialize
    super
  end

  def run(argv)
    @argv, @option = PerfMonger::Command::StatOption.parse(argv)

    if @argv.size == 0
      puts("ERROR: No command given.")
      exit(false)
    end

    # Search perfmonger-record binary: First, search perfmonger-record
    # in build environment, then in installed directory
    record_bin = [File.expand_path("../../../../perfmonger-record", __FILE__),
                  File.expand_path("perfmonger-record", PerfMonger::BINDIR)].find do |bin|
      File.executable?(bin)
    end

    if record_bin.nil?
      puts("ERROR: perfmonger-record not found!")
      exit(false)
    end

    record_cmd = @option.make_command

    begin
      record_pid = Process.spawn(*record_cmd)

      @start_time = Time.now
      command_pid = Process.spawn(*@argv)
      Process.wait(command_pid)
    ensure
      @end_time = Time.now
      Process.kill(:INT, record_pid)
      Process.wait(record_pid)
    end

    show_summary(@option.logfile)
  end

  def read_logfile(logfile)
    File.read(logfile).lines.map do |line|
      begin
        JSON.parse(line)
      rescue JSON::ParserError => err
        nil
      end
    end.compact
  end

  def make_summary(records)
    if records.empty?
      return nil
    elsif records.size == 1
      return records.first
    end

    # setup getters and setters all attributes for avg. calculation
    # getter.call(record) returns value
    # setter.call(record, value) set value
    # getters and setters include attribute info as a closure
    getters = []
    setters = []

    if records.first.include?("ioinfo")
      records.first["ioinfo"]["devices"].each do |device|
        records.first["ioinfo"][device].keys.each do |attr|
          getters << lambda do |record|
            record["ioinfo"][device][attr]
          end
          setters << lambda do |record, value|
            record["ioinfo"][device][attr] = value
          end
        end
      end
    end

    if records.first.include?("cpuinfo")
      records.first["cpuinfo"]["all"].keys.each do |attr|
        getters << lambda do |record|
          record["cpuinfo"]["all"][attr]
        end
        setters << lambda do |record, value|
          record["cpuinfo"]["all"][attr] = value
        end
      end

      records.first["cpuinfo"]["nr_cpu"].times do |cpu_idx|
        records.first["cpuinfo"]["cpus"][cpu_idx].keys.each do |attr|
          getters << lambda do |record|
            record["cpuinfo"]["cpus"][cpu_idx][attr]
          end
          setters << lambda do |record, value|
            record["cpuinfo"]["cpus"][cpu_idx][attr] = value
          end
        end
      end
    end

    avg_record = Marshal.load(Marshal.dump(records.first)); # deep copy

    setters.each do |setter|
      setter.call(avg_record, 0.0)
    end

    (1..(records.size - 1)).each do |idx|
      record = records[idx]

      last_t = records[idx - 1]["time"]
      t      = record["time"]

      getters.size.times do |_etters_idx|
        getter = getters[_etters_idx]
        setter = setters[_etters_idx]

        setter.call(avg_record,
                    getter.call(avg_record) + getter.call(record) * (t - last_t))
      end
    end

    getters.size.times do |_etters_idx|
      getter = getters[_etters_idx]
      setter = setters[_etters_idx]

      setter.call(avg_record,
                  getter.call(avg_record) / (records[-1]["time"] - records[0]["time"]))
    end


    # r_await/w_await need special handling
    if records.first.include?("ioinfo")
      records.first["ioinfo"]["devices"].each do |device|
        accum_r_io_time = 0.0
        accum_w_io_time = 0.0
        r_io_count = 0
        w_io_count = 0

        (records.size - 1).times do |idx|
          rec0 = records[idx]
          rec1 = records[idx + 1]
          dev_ioinfo = rec1["ioinfo"][device]
          dt = rec1["time"] - rec0["time"]

          accum_r_io_time += dev_ioinfo["r_await"] * dev_ioinfo["r/s"] * dt
          accum_w_io_time += dev_ioinfo["w_await"] * dev_ioinfo["w/s"] * dt
          r_io_count += dev_ioinfo["r/s"] * dt
          w_io_count += dev_ioinfo["w/s"] * dt
        end

        avg_record["ioinfo"][device]["r_await"] = accum_r_io_time / r_io_count
        avg_record["ioinfo"][device]["w_await"] = accum_w_io_time / w_io_count
      end
    end

    avg_record
  end

  def show_summary(logfile)
    records = read_logfile(logfile)
    summary = make_summary(records)

    puts("")
    puts("== Performance summary of '#{@argv.join(" ")}' ==")
    printf("Execution time: %.4f\n", @end_time - @start_time)

    if summary.nil?
      puts("")
      puts("No performance info was collected.")
      puts("This is because command execution time was too short, or something went wrong.")
    end

    if summary && summary["cpuinfo"]
      usr, sys, iowait, irq, soft, other =
        [summary['cpuinfo']['all']['%usr'] + summary['cpuinfo']['all']['%nice'],
         summary['cpuinfo']['all']['%sys'],
         summary['cpuinfo']['all']['%iowait'],
         summary['cpuinfo']['all']['%irq'],
         summary['cpuinfo']['all']['%soft'],
         [100.0 - summary['cpuinfo']['all']['%idle'], 0.0].max].map do |value|
        sprintf("% 2.3f", value)
      end

      puts("")
      puts("* Average CPU usage")
      puts("     %usr: #{usr}")
      puts("     %sys: #{sys}")
      puts("  %iowait: #{iowait}")
      puts("     %irq: #{irq}")
      puts("    %soft: #{soft}")
      puts("   %other: #{other}")
    end

    if summary && summary['ioinfo']
      summary['ioinfo']['devices'].each do |device|
        r_iops, w_iops, r_sec, w_sec, r_await, w_await =
          [summary['ioinfo'][device]['r/s'],
           summary['ioinfo'][device]['w/s'],
           summary['ioinfo'][device]['rsec/s'] * 512 / 1024.0 / 1024.0,
           summary['ioinfo'][device]['wsec/s'] * 512 / 1024.0 / 1024.0,
           summary['ioinfo'][device]['r_await'],
           summary['ioinfo'][device]['w_await']]

        r_iops, w_iops, r_sec, w_sec = [r_iops, w_iops, r_sec, w_sec].map do |value|
          sprintf("%.2f", value)
        end

        r_await, w_await = [r_await, w_await].map do |await|
          if await < 1.0
            sprintf("%.1f usec", await * 1000)
          else
            sprintf("%.2f msec", await)
          end
        end

        puts("")
        puts("* Average DEVICE usage: #{device}")
        puts("        read IOPS: #{r_iops}")
        puts("       write IOPS: #{w_iops}")
        puts("  read throughput: #{r_sec} MB/s")
        puts(" write throughput: #{w_sec} MB/s")
        puts("     read latency: #{r_await}")
        puts("    write latency: #{w_await}")
      end
    end
  end

  private
end

end # module Command
end # module PerfMonger
