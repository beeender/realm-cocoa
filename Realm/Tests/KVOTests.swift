////////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import XCTest
import RealmSwift

var pkCounter = 0
func nextPrimaryKey() -> Int {
    return ++pkCounter
}

class KVOObject: Object {
    dynamic var pk = nextPrimaryKey() // primary key for equality
    var ignored: Int = 0

    dynamic var boolCol: Bool = false
    dynamic var int8Col: Int8 = 1
    dynamic var int16Col: Int16 = 2
    dynamic var int32Col: Int32 = 3
    dynamic var int64Col: Int64 = 4
    dynamic var floatCol: Float = 5
    dynamic var doubleCol: Double = 6
    dynamic var stringCol: String = ""
    dynamic var binaryCol: NSData = NSData()
    dynamic var dateCol: NSDate = NSDate(timeIntervalSince1970: 0)
    dynamic var objectCol: KVOObject?
    dynamic var arrayCol = List<KVOObject>()

    override class func primaryKey() -> String { return "pk" }
    override class func ignoredProperties() -> [String] { return ["ignored"] }
}

class KVOTests: TestCase {
    // get an object that should be observed for the given object being mutated
    // used by some of the subclasses to observe a different accessor for the same row
    func observableForObject(obj: KVOObject) -> KVOObject {
        return obj
    }

    func createObject() -> KVOObject {
        return KVOObject()
    }

    var changeDictionary: [NSObject: AnyObject]?
    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<Void>) {
        changeDictionary = change
    }

    func observeChange(obj: NSObject, _ key: String, _ old: AnyObject, _ new: AnyObject, fileName: String = __FILE__, lineNumber: UInt = __LINE__, _ block: () -> Void) {
        obj.addObserver(self, forKeyPath: key, options: .Old | .New, context: nil)
        block()
        obj.removeObserver(self, forKeyPath: key)

        XCTAssert(changeDictionary != nil, "Did not get a notification", file: fileName, line: lineNumber)
        if changeDictionary == nil {
            return
        }

        let actualOld: AnyObject = changeDictionary![NSKeyValueChangeOldKey]!
        let actualNew: AnyObject = changeDictionary![NSKeyValueChangeNewKey]!
        XCTAssert(actualOld.isEqual(old), "Old value: expected \(old), got \(actualOld)", file: fileName, line: lineNumber)
        XCTAssert(actualNew.isEqual(new), "New value: expected \(new), got \(actualNew)", file: fileName, line: lineNumber)

        changeDictionary = nil
    }
}

class KVOStandaloneObjectTests: KVOTests {
    func testAddToRealmAfterAddingObservers() {
        var obj = createObject()
        observeChange(obj, "int32Col", 3, 10) {
            let realm = Realm()
            realm.write {
                realm.add(obj)
                obj.int32Col = 10
            }
        }

        obj = createObject()
        observeChange(obj, "ignored", 0, 15) {
            let realm = Realm()
            realm.write { realm.add(obj) }
            obj.ignored = 15
        }
    }
}

class KVOCommonTests: KVOTests {
    func testAllPropertyTypes() {
        let obj = createObject()
        observeChange(obj, "boolCol", false, true) { obj.boolCol = true }
        observeChange(obj, "int8Col", 1, 10) { obj.int8Col = 10 }
        observeChange(obj, "int16Col", 2, 10) { obj.int16Col = 10 }
        observeChange(obj, "int32Col", 3, 10) { obj.int32Col = 10 }
        observeChange(obj, "int64Col", 4, 10) { obj.int64Col = 10 }
        observeChange(obj, "floatCol", 5, 10) { obj.floatCol = 10 }
        observeChange(obj, "doubleCol", 6, 10) { obj.doubleCol = 10 }
        observeChange(obj, "stringCol", "", "abc") { obj.stringCol = "abc" }
        observeChange(obj, "objectCol", NSNull(), obj) { obj.objectCol = obj }

        let data = "abc".dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
        observeChange(obj, "binaryCol", NSData(), data) { obj.binaryCol = data }

        let date = NSDate(timeIntervalSince1970: 1)
        observeChange(obj, "dateCol", NSDate(timeIntervalSince1970: 0), date) { obj.dateCol = date }

        // List
    }
}

class KVOPersistedObjectTests: KVOCommonTests {
    var realm: Realm! = nil

    override func setUp() {
        super.setUp()
        realm = Realm()
        realm.beginWrite()
    }

    override func tearDown() {
        realm.cancelWrite()
        realm = nil
        super.tearDown()
    }

    override func createObject() -> KVOObject {
        let obj = KVOObject()
        realm.add(obj)
        return obj
    }
}

class KVOMultipleAccessorsTests: KVOPersistedObjectTests {
    override func observableForObject(obj: KVOObject) -> KVOObject {
        return realm.objectForPrimaryKey(KVOObject.self, key: obj.pk)!
    }
}
