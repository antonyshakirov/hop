-- SwiftPM uses these only to discover SDK metadata. Its compiler processes
-- are launched directly and keep the complete official Swift matcher list.
function RegisterExtraConfig()
    local matchers = GetRegisteredMatchers('swift')
    table.insert(matchers, 1, CreatePatternMatcher({ '^xcrun$', '^xcodebuild$', '^clang$', '^ld$', '^swift%-plugin%-server$', '^git$' }, MatchCompilerName, nil, { trace = false }))
    return { swift = matchers }
end
function GetCompatibleVersions()
    return { '1.0.0' }
end
