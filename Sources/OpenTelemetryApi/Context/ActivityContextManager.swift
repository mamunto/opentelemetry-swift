// Copyright 2020, OpenTelemetry Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import os.activity

// Bridging Obj-C variabled defined as c-macroses. See `activity.h` header.
private let OS_ACTIVITY_CURRENT = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_os_activity_current"),
                                                to: os_activity_t.self)
@_silgen_name("_os_activity_create") private func _os_activity_create(_ dso: UnsafeRawPointer?,
                                                                      _ description: UnsafePointer<Int8>,
                                                                      _ parent: Unmanaged<AnyObject>?,
                                                                      _ flags: os_activity_flag_t) -> AnyObject!

class ActivityContextManager: ContextManager {
    static let instance = ActivityContextManager()

    let rlock = NSRecursiveLock()

    class ScopeElement {
        init(scope: os_activity_scope_state_s) {
            self.scope = scope
        }

        deinit {
            //os_activity_scope_leave(&scope)
        }

        var scope: os_activity_scope_state_s
    }

    var objectScope = NSMapTable<AnyObject, ScopeElement>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    var contextMap = [os_activity_id_t: [String: AnyObject]]()

    func getCurrentContextValue(forKey key: String) -> AnyObject? {
        var parentIdent: os_activity_id_t = 0
        let activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, &parentIdent)
        var contextValue: AnyObject?
        rlock.lock()
        guard let context = contextMap[activityIdent] ?? contextMap[parentIdent] else {
            rlock.unlock()
            return nil
        }
        contextValue = context[key]
        rlock.unlock()
        return contextValue
    }

    func setCurrentContextValue(forKey key: String, value: AnyObject) {
        var parentIdent: os_activity_id_t = 0
        var activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, &parentIdent)
        rlock.lock()
        if contextMap[activityIdent] == nil || contextMap[activityIdent]?[key] != nil {
            var scope: os_activity_scope_state_s
            (activityIdent, scope) = createActivityContext()
            contextMap[activityIdent] = [String: AnyObject]()
            objectScope.setObject(ScopeElement(scope: scope), forKey: value)
        }
        contextMap[activityIdent]?[key] = value
        rlock.unlock()
    }

    func createActivityContext() -> (os_activity_id_t, os_activity_scope_state_s) {
        let dso = UnsafeMutableRawPointer(mutating: #dsohandle)
        let activity = _os_activity_create(dso, "ActivityContext", OS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT)
        let currentActivityId = os_activity_get_identifier(activity, nil)
        var activityState = os_activity_scope_state_s()
        os_activity_scope_enter(activity, &activityState)
        return (currentActivityId, activityState)
    }

    func removeContextValue(forKey key: String, value: AnyObject) {
//        var parentIdent: os_activity_id_t = 0
//        let activityIdent = os_activity_get_identifier(OS_ACTIVITY_CURRENT, &parentIdent)
//        if contextMap[activityIdent] != nil {
//            contextMap[activityIdent]![key] = nil
//            if contextMap[activityIdent]!.isEmpty {
//                contextMap[activityIdent] = nil
//            }
//        }
        if let scope = objectScope.object(forKey: value) {
            var scope = scope.scope
            os_activity_scope_leave(&scope)
        }
    }
}
