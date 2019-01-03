// Copyright (c) 2019 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

/**
 Represents an error, which happened during Implode decompression.
 It may indicate that either data is damaged or it might not be compressed with Implode at all.
 */
public enum ImplodeError: Error {
    case corruptedData
}
