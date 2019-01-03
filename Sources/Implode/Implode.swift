// Copyright (c) 2019 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

public enum Implode: DecompressionAlgorithm {

    public static func decompress(data: Data) throws -> Data {
        let reader = LsbBitReader(data: data)
        return try decompress(reader)
    }

    static func decompress(_ bitReader: LsbBitReader) throws -> Data {
        fatalError("Unimplemented")
    }

}
