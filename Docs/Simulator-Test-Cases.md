# Simulator Test Cases

## Recorded acceptance flow

| Scenario | Expected result | Recorded result |
| --- | --- | --- |
| Load video library | Existing videos appear with size and metadata | Passed |
| Enter selection mode | Selection controls appear and an item can be selected | Passed |
| Configure compression | HEVC, Small, and a 20% ratio can be selected | Passed |
| Low-bitrate protection | A warning appears and requires explicit confirmation | Passed |
| Background continuation | Compression continues after pressing Home and returning | Passed |
| Automatic refresh | The new copy appears without manually refreshing | Passed |
| Relationship verification | The source is marked Verified and the compressed child is shown | Passed |
| Preview result | The generated video opens and closes correctly | Passed |
| Safe deletion | The destructive alert has an explicit Cancel action | Passed; deletion cancelled |
| Backup and restore | Export and Import actions are visible with scope explained | Passed |

## Additional regression cases

| Scenario | Expected result |
| --- | --- |
| Multi-item selection | Multiple rows can be selected and the selected count updates |
| Two-finger selection gesture | A two-finger vertical pan extends the selection instead of scrolling |
| Compression cancellation | Cancelling stops further work and leaves originals untouched |
| App relaunch | Persisted scan metadata and relationships return after relaunch |
| Backup round trip | Exported metadata can be imported after reinstalling the app |
| Screenshot empty state | The Image screen explains when no screenshot assets are available |
| Permission denial | The app explains the missing Photos permission and offers recovery guidance |
| Insufficient storage | Compression fails safely without deleting or corrupting the original |

## Environment

- iPhone simulator
- iOS 27.0
- Synthetic video assets only
- Destructive actions were cancelled during recording
