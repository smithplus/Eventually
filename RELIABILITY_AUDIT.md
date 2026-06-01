# Reliability Audit — June 2026

> Comprehensive audit of Eventually's AuthService, GoogleTasksService, and UI layer for reliability issues, edge cases, and potential data loss scenarios.

---

## ✅ FIXED (Critical)

### AuthService

1. **Token refresh race condition** (lines 154-167)
   - **Issue**: Concurrent requests could both create refresh tasks → refresh-token reuse → auth loop
   - **Fix**: Atomic check-and-create pattern
   - **Impact**: Prevents auth loops requiring re-signin

2. **Refresh token not cleared on failure** (line 231)
   - **Issue**: Failed refresh kept stale token → infinite retry loop
   - **Fix**: Clear `refreshToken` and keychain on failure
   - **Impact**: Prevents infinite retry loops

3. **Sign-out doesn't cancel in-flight refresh** (line 139)
   - **Issue**: Refresh completing after sign-out could re-authenticate user
   - **Fix**: Cancel `refreshInFlight` task on sign-out
   - **Impact**: User can fully sign out even during refresh

4. **Token expiry buffer too tight** (line 155)
   - **Issue**: 1-second check could return tokens expiring mid-request
   - **Fix**: Require 5-second buffer
   - **Impact**: Fewer sporadic 401 errors

5. **Sign-out state leakage** (line 145)
   - **Issue**: `codeVerifier`, `error`, `didReceiveCallback` not cleared
   - **Fix**: Clear all auth state on sign-out
   - **Impact**: Cleaner state transitions

### GoogleTasksService

6. **Missing reconciliation in complete/delete/setDueDate** (lines 245-313)
   - **Issue**: If server succeeds but response fails to decode, local state diverges
   - **Fix**: Added `await reconcile(listId)` in catch blocks
   - **Impact**: **Prevents data loss** from stale local state

### UI Layer

7. **Selection dangling after list deletion** (line 536)
   - **Issue**: Deleting a list left selected task IDs orphaned → bulk actions on ghosts
   - **Fix**: Clear `selectedTaskIDs` when deleting a list
   - **Impact**: Prevents bulk actions on deleted tasks

8. **Collapsed groups referencing deleted lists** (line 536)
   - **Issue**: Deleted list IDs stayed in `collapsedGroups` forever
   - **Fix**: Remove deleted list from `collapsedGroups`
   - **Impact**: Prevents stale collapsed state

9. **Badge logic redundant when grouped** (lines 676-695)
   - **Issue**: Date badges shown when grouped by date (redundant with header)
   - **Fix**: Hide date badges when grouped by date; hide list badges when grouped by list
   - **Impact**: Cleaner UI, less visual clutter

---

## 🟡 IDENTIFIED (Not Yet Fixed)

### AuthService (Moderate)

10. **OAuth grace period too short** (line 118)
    - **Issue**: 1.5s timeout can cancel legitimate slow sign-ins
    - **Recommendation**: Increase to 5-10s
    - **Severity**: MODERATE - false-positive cancellations on slow networks

11. **OAuth server not cleaned up on error** (line 76)
    - **Issue**: If `exchangeCode` throws, `localServer` leaks
    - **Recommendation**: Wrap in `defer { localServer?.stop() }`
    - **Severity**: MODERATE - port leak until object deallocated

12. **Network failures - no retry logic** (line 224)
    - **Issue**: Transient network errors require manual re-signin
    - **Recommendation**: Add exponential backoff (3 attempts)
    - **Severity**: MODERATE - poor UX during transient failures

### GoogleTasksService (Moderate)

13. **Concurrent mutation races** (lines 346-360)
    - **Issue**: No locking; rapid taps or parallel batches can race
    - **Recommendation**: Debounce UI or add in-flight task ID set
    - **Severity**: HIGH - duplicate requests, lost updates

14. **Batch partial failures not reported** (lines 346-360)
    - **Issue**: If 3/5 tasks in a batch fail, user only sees last error
    - **Recommendation**: Aggregate errors: "2 task(s) failed to complete"
    - **Severity**: MEDIUM - silent partial failures

15. **Deleted list still viewable** (line 68)
    - **Issue**: Selection doesn't auto-switch when list is deleted
    - **Recommendation**: Check if deleted list is selected, switch to `.all`
    - **Severity**: MEDIUM - confusing UX (empty view)

16. **Empty list title not validated** (line 55)
    - **Issue**: `renameList("")` sends to API, fails with 400
    - **Recommendation**: Guard against empty titles
    - **Severity**: LOW - raw API error shown

17. **Refresh coalescing missing** (line 17)
    - **Issue**: Rapid "Refresh" taps fire duplicate fetches
    - **Recommendation**: Standard fetch coalescing pattern
    - **Severity**: LOW - wasteful, not dangerous

### UI Layer (Moderate)

18. **Draft lost on sign-out** (QuickAddWindowController)
    - **Issue**: Draft is in-memory only; sign-out or quit loses it
    - **Recommendation**: Persist to UserDefaults
    - **Severity**: CRITICAL - **data loss**

19. **Empty list keyboard navigation edge case** (line 837)
    - **Issue**: If list is empty but focused, shortcuts do nothing (confusing)
    - **Recommendation**: Auto-exit list nav when view becomes empty
    - **Severity**: LOW - confusing UX, no crash

20. **Autocomplete with very long input** (hashFragment)
    - **Issue**: Pasting 10K chars starting with `#` could lag
    - **Recommendation**: Limit fragment to 100 chars
    - **Severity**: LOW - unlikely input

21. **Expanded state lost when task moves lists** (TaskRowView line 339)
    - **Issue**: Editing task, move to another list → edits lost
    - **Recommendation**: Store expanded IDs in parent view
    - **Severity**: MODERATE - data loss during editing

22. **Error banner no dismiss button** (line 605)
    - **Issue**: Error stays until next successful operation
    - **Recommendation**: Add X button to dismiss
    - **Severity**: LOW - UX polish

---

## 📊 Summary

| Component | Critical Fixed | Moderate Identified | Low Identified |
|-----------|----------------|---------------------|----------------|
| **AuthService** | 5 | 3 | 0 |
| **GoogleTasksService** | 1 | 5 | 1 |
| **UI Layer** | 2 | 2 | 4 |
| **TOTAL** | **8** | **10** | **5** |

---

## 🎯 Recommended Next Steps (Priority Order)

1. ✅ **DONE**: Fix token refresh race → auth loop prevention
2. ✅ **DONE**: Clear refresh token on failure → no infinite retries
3. ✅ **DONE**: Cancel refresh on sign-out → reliable sign-out
4. ✅ **DONE**: Add reconciliation to complete/delete/setDueDate → data loss prevention
5. ✅ **DONE**: Clear selection + collapsed groups on list delete → no ghost operations
6. ✅ **DONE**: Fix badge logic when grouped → cleaner UI
7. **TODO**: Persist draft to UserDefaults → prevent data loss on sign-out
8. **TODO**: Add concurrent mutation guards → prevent duplicate requests
9. **TODO**: Aggregate batch operation errors → better UX for partial failures
10. **TODO**: Increase OAuth grace period → reduce false cancellations
11. **TODO**: Add exponential backoff for refresh failures → better transient error handling

---

## 🔬 Testing Recommendations

### Critical Path Tests

1. **Auth loop prevention**:
   - Trigger 5 concurrent API calls with expired token
   - Verify only 1 refresh request is sent
   - Verify no auth loop if refresh fails

2. **Data loss prevention**:
   - Complete task while network is disconnected
   - Verify reconciliation fetches correct state
   - Delete task while server times out → verify reconciliation

3. **Selection edge cases**:
   - Select 3 tasks in List A
   - Delete List A
   - Verify selection is cleared
   - Verify no ghost operations

4. **Badge logic**:
   - Group by date → verify no date badges on tasks
   - Group by list → verify no list badges on tasks
   - No grouping → verify both badges show

### Stress Tests

- **Rapid mutations**: Tap "Complete" 10x in 1 second → verify no duplicates
- **Concurrent batches**: Select 5 tasks, hit Complete, immediately select 5 more, hit Delete
- **Network chaos**: Disconnect mid-mutation → verify reconciliation
- **Sign-out during refresh**: Sign out while token is refreshing → verify clean exit

---

**Audit Date**: June 1, 2026  
**Audited By**: Claude (3 specialized agents: AuthService, GoogleTasksService, UI Layer)  
**Critical Fixes Applied**: 9  
**Outstanding Issues**: 15 (10 moderate, 5 low)
