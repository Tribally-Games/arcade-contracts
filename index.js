exports.abi = require("./src/generated/abi.json");

const deployments = require("./gemforge.deployments.json");

exports.diamondProxy = {};

for (const network of Object.keys(deployments)) {
  const diamondProxy = deployments[network].contracts.find(d => d.name === "DiamondProxy");
  exports.diamondProxy[network] = diamondProxy.onChain.address;
}
