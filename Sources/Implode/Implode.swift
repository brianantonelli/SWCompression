// Copyright (c) 2019 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

public enum Implode: DecompressionAlgorithm {

    public static func decompress(data: Data) throws -> Data {
        let reader = LsbBitReader(data: data)
        let ascii = reader.byte() == 1
        guard let dictSize = Implode.DictionarySize(reader.byte())
            else { throw ImplodeError.corruptedData }
        return try decompress(reader, ascii, dictSize)
    }

    static func decompress(_ reader: LsbBitReader, _ ascii: Bool, _ dictSize: Implode.DictionarySize) throws -> Data {
        var out = [UInt8]()

        let literalTree = ascii ? decodeTree(reader) : nil
        let lengthTree = decodeTree(reader)
        let distanceTree = decodeTree(reader)

        let minMatchLength = ascii ? 3 : 2

        while !reader.isFinished {
            let controlBit = reader.bit()

            if controlBit != 0 {
                if literalTree != nil {
                    let literalSymbol = literalTree!.implodeFindNextSymbol()
                    guard literalSymbol != -1
                        else { break }
                    out.append(literalSymbol.toUInt8())
                } else {
                    guard reader.bitsLeft >= 8
                        else { break }
                    out.append(reader.byte(fromBits: 8))
                }
            } else {
                var distance = 0
                // TODO: Does distance tree always encode high 6 bits of distance for all (even standalone) dict sizes?
                let distanceBitCount: Int
                switch dictSize {
                case .eight:
                    distanceBitCount = 7
                case .four:
                    distanceBitCount = 6
                default:
                    fatalError("Not implemented")
                }
                guard reader.bitsLeft >= distanceBitCount
                    else { break }
                distance |= reader.int(fromBits: distanceBitCount)
                let distanceSymbol = distanceTree.implodeFindNextSymbol()
                guard distanceSymbol != -1
                    else { break }
                distance |= distanceSymbol << distanceBitCount

                let lengthSymbol = lengthTree.implodeFindNextSymbol()
                guard lengthSymbol != -1
                    else { break }
                var length = minMatchLength + lengthSymbol
                if lengthSymbol == 63 {
                    guard reader.bitsLeft >= 8
                        else { break }
                    length += reader.int(fromBits: 8)
                }

//                assert(distance >= length) // TODO: ???

                var copyIndex = out.count - distance - 1
                while copyIndex < 0 && length > 0 {
                    out.append(0)
                    copyIndex += 1
                    length -= 1
                }
                while length > 0 {
                    out.append(out[copyIndex])
                    copyIndex += 1
                    length -= 1
                }

//                assert(copyIndex == out.count) // TODO: ???
                assert(length == 0) // TODO: ???
            }
        }

        return Data(bytes: out)
    }

    private static func decodeTree(_ reader: LsbBitReader) -> DecodingTree {
        let codeCount = reader.byte() + 1
        var bootstrap = [(symbol: Int, codeLength: Int)]()
        var symbol = 0
        for _ in 0..<codeCount {
            let bitLength = reader.int(fromBits: 4) + 1
            /// Number of codes with this bit length.
            let bitLengthCodeCount = reader.int(fromBits: 4) + 1
            bootstrap.append((symbol, bitLength))
            symbol += bitLengthCodeCount
        }
        bootstrap.append((symbol, -1))
        precondition(reader.isAligned, "Reader is not aligned after decoding Implode's Shannon-Fano tree")
        let codes = Implode.shannonFanoCodes(from: CodeLength.lengths(from: bootstrap))
        return DecodingTree(codes: codes.codes, maxBits: codes.maxBits, reader)
    }

    /// `lengths` don't have to be sorted, but there must not be any 0 code lengths.
    private static func shannonFanoCodes(from lengths: [CodeLength]) -> (codes: [Code], maxBits: Int) {
        // Sort `lengths` array to calculate canonical Huffman code.
        let sortedLengths = lengths.sorted()

        // Calculate maximum amount of leaves possible in a tree.
        let maxBits = sortedLengths.last!.codeLength
        var codes = [Code]()
        codes.reserveCapacity(sortedLengths.count)

        var code = 0
        var codeIncrement = 0
        var lastBitLength = 0
        for i in stride(from: sortedLengths.count - 1, through: 0, by: -1) {
            code = code + codeIncrement
            if sortedLengths[i].codeLength != lastBitLength {
                lastBitLength = sortedLengths[i].codeLength
                codeIncrement = 1 << (16 - lastBitLength)
            }
            let sfCode = code.reversed(bits: 16)
            codes.append(Code(bits: sortedLengths[i].codeLength, code: sfCode, symbol: sortedLengths[i].symbol))
        }
        return (codes, maxBits)
    }

}
