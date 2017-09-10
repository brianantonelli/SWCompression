// Copyright (c) 2017 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

public extension BZip2 {

    public static func compress(data: Data) -> Data {
        var out = [UInt8]()

        // Run Length Encoding
        var index = 0
        while index < data.count {
            var runLength = 1
            while index + 1 < data.count && data[index] == data[index + 1] && runLength <= 255 {
                runLength += 1
                index += 1
            }
            if runLength >= 4 {
                for _ in 0..<4 {
                    out.append(data[index])
                }
                out.append(runLength.toUInt8() - 4)
            } else {
                for _ in 0..<runLength {
                    out.append(data[index])
                }
            }
            index += 1
        }

        // BWT
        let suffixArray = SuffixArray.make(from: out, with: 256)
        var bwt = [UInt8]()
        var pointer = 0
        for i in 1..<suffixArray.count {
            if suffixArray[i] > 0 {
                bwt.append(out[suffixArray[i] - 1])
            } else {
                bwt.append(out.last!)
                pointer = i - 1
            }
        }
        out = bwt

        // Move to front
        var usedBytes = Set(out).sorted()
        for i in 0..<out.count {
            let index = usedBytes.index(of: out[i])!
            out[i] = index.toUInt8()
            let oldByte = usedBytes.remove(at: index)
            usedBytes.insert(oldByte, at: 0)
        }

        // RLE of MTF
        var zeroRunLength = 0
        var symbolOut = [Int]()
        var maxSymbol = 1
        for byte in out {
            if byte == 0 {
                zeroRunLength += 1
            } else {
                if zeroRunLength > 0 {
                    let digitsNumber = floor(log2(Double(zeroRunLength) + 1))
                    var remainder = zeroRunLength
                    for _ in 0..<Int(digitsNumber) {
                        let quotient = Int(ceil(Double(remainder) / 2) - 1)
                        let digit = remainder - quotient * 2
                        if digit == 1 {
                            symbolOut.append(0)
                        } else {
                            symbolOut.append(1)
                        }
                        remainder = quotient
                    }
                    zeroRunLength = 0
                }
                let newSymbol = byte.toInt() + 1
                // We add one because, 1 is used as RUNB.
                // We don't add two instead, because 0 is never encountered as separate symbol,
                //  without RUNA meaning.
                symbolOut.append(newSymbol)
                if newSymbol > maxSymbol {
                    maxSymbol = newSymbol
                }
            }
        }
        // In case last symbols were 0.
        if zeroRunLength > 0 {
            let digitsNumber = floor(log2(Double(zeroRunLength) + 1))
            var remainder = zeroRunLength
            for _ in 0..<Int(digitsNumber) {
                let quotient = Int(ceil(Double(remainder) / 2) - 1)
                let digit = remainder - quotient * 2
                if digit == 1 {
                    symbolOut.append(0)
                } else {
                    symbolOut.append(1)
                }
                remainder = quotient
            }
        }
        // Add 'end of stream' symbol.
        symbolOut.append(maxSymbol + 1)

        // Huffman Coding
        let bitWriter = BitWriter(bitOrder: .straight)

        // First, we analyze data and create Huffman trees and selectors.
        // Then we will perform encoding itself.
        // These are separate stages because all information about trees is stored at the beginning of the block,
        //  and it is hard to modify it later.
        var processed = 50
        var tables = [EncodingHuffmanTree]()
        var tablesLengths = [[Int]]()
        var selectorsUsed = 0
        var selectorList = [Int]()
        var stats = Array(repeating: 0, count: maxSymbol + 2)

        for i in 0..<symbolOut.count {
            let symbol = symbolOut[i]
            stats[symbol] += 1
            processed -= 1
            if processed <= 0 || i == symbolOut.count - 1 {
                processed = 50
                // We need to calculate code lengths for our current stats.
                let lengths = RecursiveHuffmanTree.build(stats).calculateLengths()
                // Using these code lengths we can create new Huffman tree, which we may use.
                let table = EncodingHuffmanTree(lengths: lengths, bitWriter)
                // Let's compute possible sizes for our stats using new tree and existing trees.
                var minimumSize = Int.max
                var minimumSelector = -1
                for tableIndex in 0..<tables.count {
                    let bitSize = tables[tableIndex].bitSize(for: stats)
                    if bitSize < minimumSize {
                        minimumSize = bitSize
                        minimumSelector = tableIndex
                    }
                }
                if table.bitSize(for: stats) < minimumSize {
                    tables.append(table)
                    tablesLengths.append(lengths.sorted { $0.symbol < $1.symbol }.map { $0.codeLength })
                    selectorList.append(tables.count - 1)
                    selectorsUsed += 1
                } else {
                    selectorList.append(minimumSelector)
                    selectorsUsed += 1
                }

                // Clear stats.
                stats = Array(repeating: 0, count: maxSymbol + 2)
            }
        }

        // Format requires at least two tables to be present.
        // If we have only one, we add a duplicate of it.
        if tables.count == 1 {
            tables.append(tables[0])
            tablesLengths.append(tablesLengths[0])
        }

        // Now, we perform encoding itself.
        // But first, we need to create block header.

        bitWriter.write(number: 0x425a, bitsCount: 16) // Magic number = 'BZ'.
        bitWriter.write(number: 0x68, bitsCount: 8) // Version = 'h'.
        bitWriter.write(number: 0x39, bitsCount: 8) // Block size. We use '9' = 900 KB for now.
        bitWriter.write(number: 0x314159265359, bitsCount: 48) // Block magic number.
        bitWriter.write(number: CheckSums.bzip2CRC32(data).toInt(), bitsCount: 32) // Block crc32.
        bitWriter.write(number: 0, bitsCount: 1) // "Randomized".
        bitWriter.write(number: pointer, bitsCount: 24) // Original pointer (from BWT).

        var usedMap = Array(repeating: UInt8(0), count: 16)
        for usedByte in usedBytes {
            if 0 <= usedByte && usedByte < 16 {
                usedMap[0] = 1
            } else if 16 <= usedByte && usedByte < 32 {
                usedMap[1] = 1
            } else if 32 <= usedByte && usedByte < 48 {
                usedMap[2] = 1
            } else if 48 <= usedByte && usedByte < 64 {
                usedMap[3] = 1
            } else if 64 <= usedByte && usedByte < 80 {
                usedMap[4] = 1
            } else if 80 <= usedByte && usedByte < 96 {
                usedMap[5] = 1
            } else if 96 <= usedByte && usedByte < 112 {
                usedMap[6] = 1
            } else if 112 <= usedByte && usedByte < 128 {
                usedMap[7] = 1
            } else if 128 <= usedByte && usedByte < 144 {
                usedMap[8] = 1
            } else if 144 <= usedByte && usedByte < 160 {
                usedMap[9] = 1
            } else if 160 <= usedByte && usedByte < 176 {
                usedMap[10] = 1
            } else if 176 <= usedByte && usedByte < 192 {
                usedMap[11] = 1
            } else if 192 <= usedByte && usedByte < 208 {
                usedMap[12] = 1
            } else if 208 <= usedByte && usedByte < 224 {
                usedMap[13] = 1
            } else if 224 <= usedByte && usedByte < 240 {
                usedMap[14] = 1
            } else if 240 <= usedByte && usedByte <= 255 {
                usedMap[15] = 1
            } else {
                fatalError("Incorrect used byte.")
            }

        }
        bitWriter.write(bits: usedMap)

        var usedBytesIndex = 0
        usedBytes.sort()
        for i in 0..<16 {
            guard usedMap[i] == 1 else { continue }
            for j in 0..<16 {
                if usedBytesIndex < usedBytes.count && i * 16 + j == usedBytes[usedBytesIndex].toInt() {
                    bitWriter.write(bit: 1)
                    usedBytesIndex += 1
                } else {
                    bitWriter.write(bit: 0)
                }
            }
        }

        bitWriter.write(number: tables.count, bitsCount: 3)
        bitWriter.write(number: selectorsUsed, bitsCount: 15)

        let mtfSelectorList = mtf(selectorList)
        for selector in mtfSelectorList {
            if selector == 0 {
                bitWriter.write(bit: 0)
            } else if selector == 1 {
                bitWriter.write(bits: [1, 0])
            } else if selector == 2 {
                bitWriter.write(bits: [1, 1, 0])
            } else if selector == 3 {
                bitWriter.write(bits: [1, 1, 1, 0])
            } else if selector == 4 {
                bitWriter.write(bits: [1, 1, 1, 1, 0])
            } else if selector == 5 {
                bitWriter.write(bits: [1, 1, 1, 1, 1, 0])
            } else {
                fatalError("Incorrect selector.")
            }
        }

        // Delta bit lengths.
        for lengths in tablesLengths {
            // Starting length.
            var currentLength = lengths[0]
            bitWriter.write(number: currentLength, bitsCount: 5)
            for length in lengths {
                while currentLength != length {
                    bitWriter.write(bit: 1) // Alter length.
                    if currentLength > length {
                        bitWriter.write(bit: 1) // Decrement length.
                        currentLength -= 1
                    } else {
                        bitWriter.write(bit: 0) // Increment length.
                        currentLength += 1
                    }
                }
                bitWriter.write(bit: 0)
            }
        }

        // Contents.
        var encoded = 0
        var selectorPointer = 0
        var t: EncodingHuffmanTree?
        for symbol in symbolOut {
            encoded -= 1
            if encoded <= 0 {
                encoded = 50
                if selectorPointer <= selectorList.count {
                    t = tables[selectorList[selectorPointer]]
                    selectorPointer += 1
                }
            }
            t?.code(symbol: symbol)
        }

        // EOS magic number.
        bitWriter.write(number: 0x177245385090, bitsCount: 48)
        // Total crc32.
        bitWriter.write(number: CheckSums.bzip2CRC32(data).toInt(), bitsCount: 32)

        bitWriter.finish()

        return Data(bytes: bitWriter.buffer)
    }

    static func mtf(_ array: [Int]) -> [Int] {
        var result = [Int]()
        var mtf = Array(0..<array.count)
        for i in 0..<array.count {
            let index = mtf.index(of: array[i])!
            result.append(index)
            let old = mtf.remove(at: index)
            mtf.insert(old, at: 0)
        }
        return result
    }

}
