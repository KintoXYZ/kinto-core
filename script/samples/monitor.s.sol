// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@aa/core/EntryPoint.sol";

import "../../src/KintoID.sol";
import "../../test/helpers/AASetup.sol";

import "forge-std/console.sol";
import "forge-std/Script.sol";

/// @notice This script calls the monitor function of the KintoID
/// @dev Needs to be called by an address with KYC_PROVIDER_ROLE
contract KintoMonitorScript is AASetup {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoID _kintoID;
    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;

    function setUp() public {
        (_kintoID, _entryPoint, _walletFactory,) = _checkAccountAbstraction();
        console.log("All AA setup is correct");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer is", vm.addr(deployerPrivateKey));

        address[] memory _addressesToMonitor = new address[](0);
        KintoID.MonitorUpdateData[][] memory _traitsAndSanctions = new IKintoID.MonitorUpdateData[][](0);
        console.log("Update monitoring - no traits or sanctions update");

        // NOTE: must be called from KYC_PROVIDER_ROLE
        console.log("Sender has KYC_PROVIDER_ROLE:", _kintoID.hasRole(_kintoID.KYC_PROVIDER_ROLE(), msg.sender));
        vm.broadcast(deployerPrivateKey);
        _kintoID.monitor(_addressesToMonitor, _traitsAndSanctions);
    }
}
