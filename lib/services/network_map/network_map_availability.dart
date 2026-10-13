/// The network map stays unreachable in this fork. Upstream's opt-in upload
/// of header-only packet records to map.meshcoreopen.org and its online
/// repeater layer are kept in the tree for later merges, but while this is
/// false no upload service is created, the opt-in question is never asked,
/// the settings section is not shown and the map draws the local view only.
/// Flip it once the fork has decided where its users' packet records should
/// go, if anywhere.
const bool networkMapAvailable = false;
