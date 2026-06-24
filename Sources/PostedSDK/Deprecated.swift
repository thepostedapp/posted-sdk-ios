import Foundation

// Deprecated type aliases for the Detour → PostedSDK rebrand.
// These shims are present for one minor release cycle only and will be removed in a future version.

@available(*, deprecated, renamed: "Posted")
public typealias Detour = Posted

@available(*, deprecated, renamed: "PostedConfig")
public typealias DetourConfig = PostedConfig

@available(*, deprecated, renamed: "PostedLink")
public typealias DetourLink = PostedLink

@available(*, deprecated, renamed: "PostedResult")
public typealias DetourResult = PostedResult

@available(*, deprecated, renamed: "PostedAnalytics")
public typealias DetourAnalytics = PostedAnalytics

@available(*, deprecated, renamed: "PostedEventName")
public typealias DetourEventName = PostedEventName
