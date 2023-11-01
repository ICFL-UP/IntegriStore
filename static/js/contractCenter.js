import { contractABI } from "./contractabi.js";
export async function getContract() {
    return new Promise(async (resolve, reject) => {
      if (typeof window.ethereum !== "undefined") {
        const contractAddr = getContractAddr();
        if (contractAddr!=="0x0") {
          const provider = new ethers.BrowserProvider(window.ethereum);
          await provider.send("eth_requestAccounts", []);
          const signer = await provider.getSigner();
          const contract = new ethers.Contract(contractAddr, contractABI, signer);
          contract;
          try {
            resolve(contract);
          } catch (error) {
            console.log(error);
            reject(error);
          }
        } else {
          alert("Invalid contract address");
          reject("Invalid contract address");
        }
      } else {
        $("#connectButton").html("Please install MetaMask");
        alert("Please install MetaMask");
        reject("Please install MetaMask");
      }
    });
  }

export function getContractAddr(){
  const e = document.getElementById("contractAddr");
  const contractAddr = e.value;
  if(contractAddr.match(/0x[0-9a-fA-F]{40}/)){
    return contractAddr;
  }
  else return "0x0"
}