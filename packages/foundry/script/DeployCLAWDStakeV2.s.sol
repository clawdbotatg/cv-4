// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/CLAWDStakeV2.sol";

contract DeployCLAWDStakeV2 is ScaffoldETHDeploy {
    // CLAWD token on Base mainnet
    address constant CLAWD_TOKEN = 0x9F86d2b6FC636C93727614d7e3D959c9dAeDeA67;
    // Contract owner = job.client
    address constant OWNER = 0x34aA3F359A9D614239015126635CE7732c18fDF3;

    function run() external ScaffoldEthDeployerRunner {
        new CLAWDStakeV2(CLAWD_TOKEN, OWNER);
    }
}
