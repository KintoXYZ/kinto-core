// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IHook} from "./IHook.sol";

interface IKintoHook is IHook {
    function setReceiver(address receiver, bool allowed) external;

    function setSender(address sender, bool allowed) external;

    function receiveAllowlist(address addr) external view returns (bool);

    function senderAllowlist(address addr) external view returns (bool);
}
