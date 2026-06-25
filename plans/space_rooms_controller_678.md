# Space Child-Room Hierarchy Controller Implementation Plan (Issue #678)

## Goal
Provide a data layer that manages and exposes the hierarchy of child rooms within a given space, specifically highlighting which rooms are not yet joined by the user, without requiring any manual interaction beyond viewing the space's children.

## Implementation Details

### 1. Data Models (`lib/features/spaces/models/space_rooms_model.dart`)
Create a model to represent the metadata of a child room as it appears in a space preview:
- `roomId`: String
- `name`: String (localized)
- `avatar`: String? (optional, if available)
- `memberCount`: int
- `roomType`: String (to distinguish between 'm.room' and 'm.space')
- `isSuggested`: bool

Create a state object for each space ID in the controller:
- `loading`: bool
- `error`: String?
- `previewForbidden`: bool
- `unjoinedRooms`: List<SpaceRoomMetadata> (ordered)
- `subspaces`: List<SpaceRoomMetadata> (ordered)

### 2. Controller Implementation (`lib/features/spaces/services/space_rooms_controller.dart`)
Create `SpaceRoomsController` as a `ChangeNotifier`.

#### Core Methods:
- **`fetchSpaceRooms(String spaceId)`**: 
    - Call `SpaceDiscoveryDataSource.getSpaceHierarchy(spaceId, maxDepth: 1, suggestedOnly: false)`.
    - Filter out the space itself and any rooms the user is already joined to.
    - Sort based on the space's child order.
    - Update internal cache and notify listeners.
  
- **`refresh(String spaceId)`**: Manual trigger to re-run `fetchSpaceRooms`.

- **`join(String roomId, {String? alias, List<String>? via})`**:
    - Call `SpaceDiscoveryDataSource.joinRoom(...)`.
    - On success, determine the parent space ID and call `refresh(parentSpaceId)`.

#### Synchronization:
- Listen to `client.onSync`. 
- When a membership change is detected, check if the changed room is a child of any cached space.
- If so, trigger a refresh for that space to ensure "unjoinedRooms" stays accurate (e.g., a newly joined room should disappear).

### 3. Integration & Registration
- Register `SpaceRoomsController` in `lib/main.dart`.

### 4. Testing Requirements
Use `FakeSpaceDiscoveryDataSource` to verify:
- Correct filtering of unjoined rooms (exclude joined and own space).
- Correct identification of subspaces.
- Error state transitions for network errors and `M_FORBIDDEN`.
- Automatic cache update after a successful `join()` call followed by sync.

## Acceptance Criteria Verification Plan
1. [ ] Verify N children with K joined results in N-K unjoined rooms.
2. [ ] Confirm self and subspaces are not in unjoined list but appear in subspace list.
3. [ ] Validate loading/error/forbidden transitions via UI/Tests.
4. [ ] Test join() triggers refresh without manual interaction.
5. [ ] Verify result caching and manual refresh capability.

## Dependencies & Resources
- `SpaceDiscoveryDataSource` (for fetching data)
- `SelectionService` (as a reference for sync listener patterns)
- `order_utils` (for correct child ordering)
