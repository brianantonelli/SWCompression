// Copyright (c) 2019 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

extension Implode {

    /**
     Represents the size of the dictionary used by Implode algorithm during compression.

     - Note: Implode algorithm used by ZIP supports only 4 and 8 kilobytes dictionaries, whereas "standalone" data
     compressed with Implode use only 1, 2 or 4 kilobytes dictionaries.
     */
    enum DictionarySize {
        /// 1 KB. Used only by standalone Implode algorithm.
        case one
        /// 2 KB. Used only by standalone Implode algorithm.
        case two
        /// 4 KB. Used by both standalone and ZIP's Implode algorithm.
        case four
        /// 8 KB. Used only by ZIP's Implode algorithm.
        case eight

        init?(_ standaloneByte: UInt8) {
            switch standaloneByte {
            case 4:
                self = .one
            case 5:
                self = .two
            case 6:
                self = .four
            default:
                return nil
            }
        }

    }

}

