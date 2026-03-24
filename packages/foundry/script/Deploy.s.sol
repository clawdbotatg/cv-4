//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployCLAWDStakeV2 } from "./DeployCLAWDStakeV2.s.sol";

contract DeployScript is ScaffoldETHDeploy {
  function run() external {
    DeployCLAWDStakeV2 deployCLAWDStakeV2 = new DeployCLAWDStakeV2();
    deployCLAWDStakeV2.run();
  }
}
