import { getContract, getContractAddr } from "./contractCenter.js";

const API_URL = ""; //empty string means same domain

// ethers has been imported globally
$(document).ready(function () {
  $("#connectButton").click(function () {
    connect();
  });

  $(".secHeader").click(function () {
    $(this).find(".chevron").toggleClass("rotated");
  });

  $("#updateView").click(function () {
    const e = document.getElementById("contractAddr");
    const contractAddr = e.value;
    if (contractAddr.match(/0x[0-9a-fA-F]{40}/)) {
      $.ajax({
        type: "GET",
        url: "/getGraph/" + contractAddr,
        success: function (response) {
          const svg = response.match(/<svg(?:.|\n|\r|\t)*<\/svg>/);
          if (svg != null && svg != undefined) {
            $("#graphViewDiv").html(svg[0]);
          }
        },
      });
    }
  });

  //Is this stupid? kinda

  $("#addRoleBtn").click(function () {
    addRole();
  });

  $("#removeRoleBtn").click(function () {
    removeRole();
    } );

  $("#grantRoleBtn").click(function () {
    grantRole();
  });

  $("#groupAddBtn").click(function () {
    groupAdd();
  });

  $("#addEvidenceBtn").click(function () {
    addEvidence();
  });

  $("#addServerBtn").click(function () {
    addServer();
  });

  $("#addGroupAccessBtn").click(function () {
    addGroupAccess();
  });


  $("#loadEvidenceBtn").click(function () {
    loadEvidence();
  });

  $("#msgSignBtn").click(function () {
    msgSign();
  });


  

});

function getHash(msg){
  const textEnc = new TextEncoder();
  return ethers.keccak256(textEnc.encode(msg));
}

function getEncoded(msg){
  const textEnc = new TextEncoder();
  return textEnc.encode(msg);
}

async function connect() {
  if (typeof window.ethereum !== "undefined") {
    try {
      await ethereum.request({ method: "eth_requestAccounts" });
    } catch (error) {
      console.log(error);
    }
    $("#connectButton").html("Connected").attr("disabled", true);
    const accounts = await ethereum.request({ method: "eth_accounts" });
    const account = accounts[0];
    $("#accStuff .acc").first().html(account);

    $("#controls").show();
  } else {
    // connectButton.innerHTML = "Please install MetaMask"
    $("#connectButton").html("Please install MetaMask");
    alert("Please install MetaMask");
  }
}

async function addRole() {
  const contract = await getContract();
  // //add new role
  // console.log($("#addRoleForm"));
  // find input with name roleName
  const roleName = $("#addRoleForm").find("input[name='roleName']").val();
  const adminName = $("#addRoleForm").find("input[name='roleAdmin']").val();

  // check for valid input
  if (roleName == "" || adminName == "") {
    alert("Invalid input");
    return;
  }

  contract.addRole(getHash(roleName), getHash(adminName)).then((tx) => {
    const provider = new ethers.BrowserProvider(window.ethereum);
    makeAlert("Role added", true);
    // provider.waitForTransaction(tx.hash).then(() => {
    // });
  });
}

async function removeRole(){
  const contract = await getContract();
  const roleName = $("#removeRoleForm").find("input[name='roleName']").val();
  if (roleName == "") {
    alert("Invalid input");
    return;
  }
  contract.removeRole(getHash(roleName)).then((tx) => {
    makeAlert("Role removed", true);
  });

}

async function groupAdd(){
  const contract = await getContract();
  const groupName = $("#groupAddForm").find("input[name='group']").val();
  const roleName = $("#groupAddForm").find("input[name='roleName']").val();
  const leader = $("#groupAddForm").find("input[name='leader']").val();
  if (groupName == "" || roleName == ""|| leader == "") {
    alert("Invalid input");
    return;
  }
  contract.addEvidenceGroup(getHash(groupName),getHash(roleName), leader).then((tx) => {
    makeAlert("Group added", true);
  });
}

async function grantRole(){
  const contract = await getContract();
  const roleName = $("#grantRoleForm").find("input[name='roleName']").val();
  const account = $("#grantRoleForm").find("input[name='user']").val();
  if (roleName == "" || account == "") {
    alert("Invalid input");
    return;
  }
  contract.grantRole(getHash(roleName), account).then((tx) => {
    makeAlert("Role granted", true);
  }
  );
}

async function addEvidence(){
  const contract = await getContract();
  const groupName = $("#addEvidenceForm").find("input[name='group']").val();
  const roleName = $("#addEvidenceForm").find("input[name='roleName']").val();
  const evidence = $("#addEvidenceForm").find("input[name='evidence']")[0].files[0];
  if(groupName == "" || evidence == undefined){
    alert("Invalid input");
    return;
  }
  const reader = new FileReader();
  reader.readAsArrayBuffer(evidence);
    reader.onload = function(e) {
      const arrayBuffer = e.target.result;
      const data = new Uint8Array(arrayBuffer);
      const md5 = "0x"+CryptoJS.SHA256(CryptoJS.lib.WordArray.create(data)).toString();
      contract.addEvidence(md5,getHash(groupName), getHash(roleName)).then((tx) => {
        makeAlert("Evidence Sent to smart contract", true);
      });
    };
}

async function addServer(){
  const contract = await getContract();
  const serverName = $("#addServerForm").find("input[name='server']").val();

  if(serverName == ""){
    alert("Invalid input");
    return;
  }
  contract.addServer(serverName).then((tx) => {
    makeAlert("Server added", true);
  }
  );
}

async function addGroupAccess(){
  const contract = await getContract();
  const group = $("#addGroupAccessForm").find("input[name='group']").val();
  const roleName = $("#addGroupAccessForm").find("input[name='roleName']").val();

  if(group == "" || roleName == ""){
    alert("Invalid input");
    return;
  }
  contract.addRoleGroup(getHash(roleName),getHash(group)).then((tx) => {
    makeAlert("Group access added", true);
  });

}

async function loadEvidence(){
  // need to load all the diff evidences
  const accounts = await ethereum.request({
    method: 'eth_requestAccounts',
  });
  const account=accounts[0];
  const contractAddr=getContractAddr();
  if (contractAddr=="0x0") {
    alert("Invalid contract address");
    return;
  }

  const request={
    "address":account,
    "contractAddress":contractAddr,
  }
  $.ajax({
    type: "POST",
    url: API_URL+"/getEvidenceList",
    data: JSON.stringify(request),
    contentType: "application/json",
    dataType: "json",
    success: function (response) {
      document.getElementById("evdiv").innerHTML="";
      //remove loadEvidenceBtn from dom
      $("#loadEvidenceBtn").remove();
      const groupTemplate=document.querySelector("#groupTemplate");
      const evidenceTemplate=document.querySelector("#evTemplate");
      response.forEach((e)=>{
        const group=document.importNode(groupTemplate.content,true);
        group.querySelector(".groupHeader").textContent=e.groupName;
        group.querySelector(".groupHash").textContent=e.groupHash;
        group.querySelector(".roleSelect").classList.add(`group_${e.groupHash}`);
        if(e.evidence.length==0){
          group.querySelector(".controls").innerHTML="";
          group.querySelector(".controls").append($("<h5>No Evidence</h5>")[0]);
        }
        else{
          //dont need roles if no evidence
          e.roles.forEach((role)=>{
            group.querySelector(".roleSelect").append(new Option(role,role));
          })
          e.evidence.forEach((ev)=>{
            const evidence=document.importNode(evidenceTemplate.content,true);
            evidence.querySelector(".card-title").textContent=ev.evidenceName;
            evidence.querySelector(".hash").textContent=ev.evidenceHash;
            evidence.querySelector(".btnDownload").onclick=()=>downloadEvidence(ev.evidenceHash,e.groupHash);
            group.querySelector(".innerEv").appendChild(evidence);
  
          })

        }

        
        document.getElementById("evdiv").appendChild(group);
      });
    }
  });

}

async function downloadEvidence(hash,groupHash){ 
  //get the role
  const role=$(`.group_${groupHash}`).val();
  const contractAddr=getContractAddr();
  if (contractAddr=="0x0") {
    alert("Invalid contract address");
    return;
  }
  const contract = await getContract();
  const tx=await contract.requestEvidence(hash,role);
  const transHash=tx.hash;
  const provider = new ethers.BrowserProvider(window.ethereum);
  const transaction=await provider.getTransactionReceipt(transHash)
  const returnHash=transaction.logs[0].topics[2];
  // now we sign the hash and make the api call
  
  // const contract = await getContract();

}

async function msgSign(){
  const msg=$("#msgSignForm").find("input[name='msg']").val();
  const accounts = await ethereum.request({
    method: 'eth_requestAccounts',
  });
  //convert msg to its unicode representation
  const msgUnicode=msg.split("").reduce((running,curr)=>running+curr.charCodeAt(0).toString(16),"0x");
  const resp=await window.ethereum.request({
    "method": "personal_sign",
    "params": [
      msgUnicode,accounts[0]
    ]
  });
  $("#msgSignForm").find(".signedMsg").text(resp);
}


function makeAlert(message, success) {
  //make new element
  const alertDiv = document.createElement("div");
  alertDiv.classList.add("alert");
  alertDiv.classList.add("alert-success");
  alertDiv.classList.add("alert-dismissible");
  alertDiv.classList.add("fade");
  alertDiv.classList.add("show");
  alertDiv.classList.add(success ? "alert-success" : "alert-danger");
  alertDiv.setAttribute("role", "alert");
  const msg = document.createTextNode(message);
  alertDiv.appendChild(msg);
  //add to page
  const alertContainer = document.getElementById("alertContainer");
  alertContainer.appendChild(alertDiv);
  //remove after 5 seconds
  setTimeout(function () {
    $(alertDiv).alert("close");
  }, 3000);
}

