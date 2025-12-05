// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

library ScriptHelpers {
    string internal constant IMPL_SUFFIX = "_Impl";
    string internal constant PROXY_SUFFIX = "_Proxy";
    string internal constant BEACON_SUFFIX = "_Beacon";

    function beacon(string memory name) internal pure returns (string memory) {
        return string.concat(name, BEACON_SUFFIX);
    }

    function impl(string memory name) internal pure returns (string memory) {
        return string.concat(name, IMPL_SUFFIX);
    }

    function proxy(string memory name) internal pure returns (string memory) {
        return string.concat(name, PROXY_SUFFIX);
    }

    function instance(string memory name, string memory index) internal pure returns (string memory) {
        return string.concat(name, "_", index);
    }
}
