# SPDX-License-Identifier: GPL-3.0-or-later
# Image sizes from file headers (PNG, JPEG, BMP) without decoding.
module RMXP3DS
  module Images
    module_function

    # [width, height] or nil for an unknown or damaged file.
    def size(path)
      File.open(path, 'rb') do |f|
        head = f.read(26) || ''
        if head.start_with?("\x89PNG\r\n\x1a\n".b) && head[12, 4] == 'IHDR'
          head[16, 8].unpack('NN')
        elsif head.start_with?('BM')
          w, h = head[18, 8].unpack('l<l<')
          [w, h.abs]
        elsif head.start_with?("\xFF\xD8".b)
          jpeg_size(f)
        end
      end
    rescue StandardError
      nil
    end

    # Walks the JPEG segments to the first start-of-frame marker.
    def jpeg_size(f)
      f.seek(2)
      loop do
        marker = f.read(2)
        return nil unless marker&.getbyte(0) == 0xFF
        code = marker.getbyte(1)
        len = f.read(2)&.unpack1('n')
        return nil unless len
        if (0xC0..0xCF).cover?(code) && ![0xC4, 0xC8, 0xCC].include?(code)
          h, w = f.read(5)[1, 4].unpack('nn')
          return [w, h]
        end
        f.seek(len - 2, IO::SEEK_CUR)
      end
    end
  end
end
