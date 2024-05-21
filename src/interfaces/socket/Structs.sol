// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

struct UpdateLimitParams {
    bool isMint;
    address connector;
    uint256 maxLimit;
    uint256 ratePerSecond;
}

struct SrcPreHookCallParams {
    address connector;
    address msgSender;
    TransferInfo transferInfo;
}

struct SrcPostHookCallParams {
    address connector;
    bytes options;
    bytes postSrcHookData;
    TransferInfo transferInfo;
}

struct DstPreHookCallParams {
    address connector;
    bytes connectorCache;
    TransferInfo transferInfo;
}

struct DstPostHookCallParams {
    address connector;
    bytes32 messageId;
    bytes connectorCache;
    bytes postHookData;
    TransferInfo transferInfo;
}

struct PreRetryHookCallParams {
    address connector;
    CacheData cacheData;
}

struct PostRetryHookCallParams {
    address connector;
    bytes32 messageId;
    bytes postRetryHookData;
    CacheData cacheData;
}

struct TransferInfo {
    address receiver;
    uint256 amount;
    bytes data;
}

struct CacheData {
    bytes identifierCache;
    bytes connectorCache;
}

struct LimitParams {
    uint256 lastUpdateTimestamp;
    uint256 ratePerSecond;
    uint256 maxLimit;
    uint256 lastUpdateLimit;
}
