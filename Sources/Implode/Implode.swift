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

    static func decompress(_ bitReader: LsbBitReader, _ ascii: Bool, _ dictSize: Implode.DictionarySize) throws -> Data {
        fatalError("Unimplemented")
    }

}
