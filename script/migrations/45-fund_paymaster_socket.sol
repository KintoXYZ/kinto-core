// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/KintoID.sol";
import "./utils/MigrationHelper.sol";
import {TestSignature} from "../../test/helpers/TestSignature.sol";

interface AccessControl {
    function grantBatchRole(bytes32[] calldata roleNames_, uint32[] calldata slugs_, address[] calldata grantees_)
        external;
}

contract KintoMigration45DeployScript is MigrationHelper, TestSignature {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address kintoSocketDeployer = ;
        // _fundWallet(vm.envAddress("TEST_KINTO_WALLET"), 0.1 ether, deployerPrivateKey);
        // _fundPaymaster(kintoSocketDeployer, 0.1 ether, deployerPrivateKey);
        _whitelistApp(kintoSocketDeployer, deployerPrivateKey);

        // KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        // console.log("Sender has KYC_PROVIDER_ROLE:", kintoID.hasRole(kintoID.KYC_PROVIDER_ROLE(), vm.addr(deployerPrivateKey)));

        // // _signatureData
        // IKintoID.SignatureData memory sigdata = _auxCreateSignature(IKintoID(address(kintoID)), vm.addr(deployerPrivateKey), deployerPrivateKey, 1713881891);
        // console.logBytes(sigdata.signature);

        // IKintoID.SignatureData memory _signatureData = IKintoID.SignatureData({
        //     signer: 0x1dBDF0936dF26Ba3D7e4bAA6297da9FE2d2428c2,
        //     nonce: 1,
        //     expiresAt: 1713881891,
        //     signature: hex"232f47118457fd4f531a0eb539feb05f2c1df11ebd36d4876b809b8213e8ad3302818557974e6a5390fe245a1b8d174bc8db103773ee8f90b8e6968afc445a191b"
        // });
        // console.logBytes(_signatureData.signature);

        // // _traits
        // uint16[] memory _traits = new uint16[](0);
        // vm.broadcast(deployerPrivateKey);
        // kintoID.mintIndividualKyc(_signatureData, _traits);
        // console.log("Update monitoring - no traits or sanctions update");
        // address[] memory _addressesToMonitor = new address[](0);
        // KintoID.MonitorUpdateData[][] memory _traitsAndSanctions = new KintoID.MonitorUpdateData[][](0);

        // vm.broadcast(deployerPrivateKey);
        // kintoID.monitor(_addressesToMonitor, _traitsAndSanctions);

        // empty array
        // bytes32[] memory _roleNames = new bytes32[](0);
        // uint32[] memory _slugs = new uint32[](0);
        // address[] memory _grantees = new address[](0);
        // bytes memory _selectorAndParams = abi.encodeWithSelector(AccessControl.grantBatchRole.selector, _roleNames, _slugs, _grantees);
        // _handleOps(_selectorAndParams, 0x8c5C4F34DffAF770a3607be5DaC5A410CFcC3992, deployerPrivateKey);
    }
}
