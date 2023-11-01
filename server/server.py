from flask import Flask,render_template,request,jsonify
from eth_account.messages import encode_defunct
from Crypto.Hash import keccak
from dotenv import load_dotenv
from nxIAC import nxIAC
import os
import json
import web3
import hashlib
import re
import mimetypes
import sqlite3

app = Flask(__name__,template_folder='../templates',static_folder='../static')
conn=sqlite3.connect('IACRC.db',check_same_thread=False)
# load db
 
load_dotenv()
URL=os.getenv('BLOCKCHAIN_RPC')
PRIVATE_KEY=os.getenv('PRIV_KEY')
PUBLIC_KEY=os.getenv('PUB_KEY')


# ---------------------------------------------------------------------------- #
#                                    Routes                                    #
# ---------------------------------------------------------------------------- #

@app.route('/')
def base_page():
    # check if there is a json file we need
    if os.path.isfile('json/contractlist.json'):
        # load in that bad boi
        with open('json/contractlist.json') as json_file:
            contractList = json.load(json_file)
        return render_template('index.html',contracts=contractList)
    else:
        return render_template('index.html')
 
@app.route('/getGraph/<contractAddress>')
def genIACGraph(contractAddress):
    displayAmount=20
    zeroHex="0x0000000000000000000000000000000000000000000000000000000000000000"
    IACGraph=nxIAC()
    roleEvents=getEvents(["RoleAdminChanged(bytes32,bytes32,bytes32)","RoleAdded(bytes32,bytes32)","RoleRemoved(bytes32)"],contractAddress)
    for event in roleEvents:
        if(event[0]=="RoleAdminChanged"):
        #     print(event)
            if(event[3]!=zeroHex):
                IACGraph.add_edge(event[1][:displayAmount],event[3][:displayAmount])
            # Check if this new role change is a removal
            if (event[1]!=zeroHex and event[2]!=zeroHex and event[3]==zeroHex):
                IACGraph.remove_edge(event[1][:displayAmount],event[2][:displayAmount])
        if(event[0]=="RoleAdded"):
            IACGraph.add_node(event[1][:displayAmount])
        elif(event[0]=="RoleRemoved"):
            IACGraph.remove_node(event[1][:displayAmount])

    return IACGraph.renderSVG()

@app.route('/uploadFile',methods=['POST'])
def uploadFile():
    # check if the post request has the file part
    if 'file' not in request.files or 'contractAddress' not in request.form or 'signature' not in request.form:
        return "Invalid request"
    # save the file to the server
    file=request.files['file']
    contractAddress=request.form['contractAddress']
    signature=request.form['signature']

    # check if the file is empty
    if file.filename == '':
        return "Invalid file"
    sha=hashlib.sha256(file.read()).hexdigest()
    file.seek(0)
    w3=web3.Web3(web3.HTTPProvider(URL))
    if w3.is_address(contractAddress) and w3.eth.get_code(contractAddress) != b'':
        try:
            encoded=encode_defunct(bytes(sha, encoding='utf8'))
            signer=w3.eth.account.recover_message(encoded,signature=signature)
            signerFixed="0x"+signer[2:].lower().rjust(64,'0')
            sha0x="0x"+sha
            event_filter=w3.eth.filter({"address": contractAddress,"fromBlock": 0,"toBlock": "latest","topics":[getHash("EvidenceAdded(bytes32,bytes32,address)"),None,sha0x,signerFixed]})
            events=event_filter.get_all_entries()
            if(len(events)>0):
                group=events[0]["topics"][1].hex()[2:]
                if not os.path.exists("Files/"+group):
                    os.makedirs("Files/"+group)
                # save the file to the server
                extension=mimetypes.guess_extension(file.content_type)
                base="Files/"+group+"/"
                with open("json/IntelliAccessControl.json") as json_file:
                    abi=json.load(json_file)
                    contract=w3.eth.contract(address=contractAddress,abi=abi)
                    nonce=w3.eth.get_transaction_count(PUBLIC_KEY)
                    singed=w3.eth.account.sign_transaction(contract.functions.saveEvidence(sha0x).build_transaction({"from":PUBLIC_KEY,"nonce":nonce}),private_key=PRIVATE_KEY)
                    w3.eth.send_raw_transaction(singed.rawTransaction)
                    file.save(os.path.join(base,sha+extension))
                    return "File uploaded successfully And added to the blockchain"
        except Exception as exception:
            print(exception)
            return "Invalid signature"
    
    return "Unable to upload file"


@app.route('/accessEvidence',methods=['POST'])
def accessEvidence():
    data=request.json
    if 'contractAddress' not in data or 'reqHash' not in data or 'signature' not in data:
        return "Invalid request"
    w3=web3.Web3(web3.HTTPProvider(URL))
    encoded=encode_defunct(bytes(data["reqHash"], encoding='utf8'))
    signer=w3.eth.account.recover_message(encoded,signature=data["signature"])
    signerFixed="0x"+signer[2:].lower().rjust(64,'0')
    access= ("EvidenceAccessed(bytes32,bytes32,address)",data["contractAddress"],None,data["reqHash"])
    if len(access)>0:
        return "Already accessed"
    accessRequest=getEventsTopic("EvidenceRequest(bytes32,bytes32,address,bytes32)",data["contractAddress"])
    if len(accessRequest)>0:
        if accessRequest[0][0]==signerFixed:
            return "Already requested"
    nonce=w3.eth.get_transaction_count(PUBLIC_KEY)
    singed=w3.eth.account.sign_transaction(contract.functions.saveEvidence(data["reqHash"]).build_transaction({"from":PUBLIC_KEY,"nonce":nonce}),private_key=PRIVATE_KEY)
    w3.eth.send_raw_transaction(singed.rawTransaction)

    return "Request sent"

@app.route('/getEvidenceList',methods=['POST'],)
def getEvidenceList():
    data=request.json
    evidence=getAllEvidence(data["contractAddress"],data["address"])
    returnList=list(map(processGroup,evidence.items()))
    return jsonify(returnList)


# ---------------------------------------------------------------------------- #
#                                 Map functions                                #
# ---------------------------------------------------------------------------- #

def processGroup(x):
    temp = getGroupName(x[0])
    return {
        "groupName": temp if temp != x[0] else "UNKNOWN",
        "groupHash": x[0],
        "evidence": list(map(processEvidence,x[1][0])),
        "roles": x[1][1]
    }

def processEvidence(x):
    temp=getEvidenceName(x)
    return {
        "evidenceName": temp if temp != x else "UNKNOWN",
        "evidenceHash": x
    }
# ---------------------------------------------------------------------------- #
#                               Helper functions                               #
# ---------------------------------------------------------------------------- #



def getEvents(topics,contractAddress,*args):
    hashAttr={}
    hashTopics=[]
    for topic in topics:
        hashTopic=getHash(topic)
        hashTopics.append(hashTopic)
        hashAttr[hashTopic]=topic
    if not re.match(r'0x[a-fA-F0-9]{40}', contractAddress):
        return []
    w3=web3.Web3(web3.HTTPProvider(URL))

    if w3.is_address(contractAddress) and w3.eth.get_code(contractAddress) != b'':
        # maybe add a check to see if its the right contract type
        event_filter = w3.eth.filter({"address": contractAddress,"fromBlock": 0,"toBlock": "latest","topics":[hashTopics,*args]})
        newTopics=map(lambda x: [hashAttr[x['topics'][0].hex()].split("(")[0]]+list(map(lambda y:y.hex(),x['topics'][1:])),event_filter.get_all_entries())
        
        return list(newTopics)
    else:
        return []

def getEventsTopic(topic,contractAddress,*args):
    w3=web3.Web3(web3.HTTPProvider(URL))
    if w3.is_address(contractAddress) and w3.eth.get_code(contractAddress) != b'':
        event_filter = w3.eth.filter({"address": contractAddress,"fromBlock": 0,"toBlock": "latest","topics":[getHash(topic)]})
        print("event",event_filter.get_all_entries())
        topicReturn=map(lambda x: list(map(lambda y:y.hex(),x["topics"][1:])), event_filter.get_all_entries())
        return list(topicReturn)
    else:
        return []



# return all Groups that a user has access to
def getAllUserAccessGroups(contractAddress,address):
    signerFixed="0x"+address[2:].lower().rjust(64,'0') # fix the signer so we can search for it
    events=getEvents(["RoleGranted(bytes32,address,address)","RoleRevoked(bytes32,address,address)"],contractAddress,None,signerFixed)
    # build the list
    roles=[]
    for event in events:
        if event[0]=="RoleGranted":
            roles.append(event[1])
        elif event[0]=="RoleRevoked":
            roles.remove(event[1])
    groupEvents=getEvents(["RoleGroupAdded(bytes32,bytes32)","RoleGroupRemoved(bytes32,bytes32)"],contractAddress,None,roles)
    # print(groupEvents)
    groups={}
    for event in groupEvents:
        if event[0]=="RoleGroupAdded":
            # groups[event[1]]=event[2]
            if event[1] in groups:
                groups[event[1]].append(event[2])
            else:
                groups[event[1]]=[event[2]]
        elif event[0]=="RoleGroupRemoved":
            groups[event[1]]=list(filter(lambda x: x!=event[2],groups[event[1]]))
            if len(groups[event[1]])==0:
                del groups[event[1]]
    return groups

def getAllEvidence(contractAddress,address):
    groups=getAllUserAccessGroups(contractAddress,address)
    evidence={}
    for group in groups:
        temp=getEventsTopic("EvidenceAdded(bytes32,bytes32,address)",contractAddress,group)
        evidence[group]=(list(map(lambda x:x[1],temp)),groups[group])
    return evidence

def recover(signature,message,bytes32V=False):
    w3=web3.Web3(web3.HTTPProvider(URL))
    encoded=encode_defunct(bytes(message, encoding='utf8'))
    signer=w3.eth.account.recover_message(encoded,signature=signature)
    if(bytes32V):
        return "0x"+signer[2:].lower().rjust(64,'0')
    else:
        return signer

def getHash(topic):
    keccakInstance=keccak.new(digest_bits=256)
    keccakInstance.update(topic.encode('utf-8'))
    return "0x"+keccakInstance.hexdigest()


# ---------------------------------------------------------------------------- #
#                              Database Functions                              #
# ---------------------------------------------------------------------------- #

def getGroupName(hash):
    c=conn.cursor()
    c.execute("SELECT name FROM groupNames WHERE id=?",(hash,))
    # check it actally exists
    result=c.fetchone()
    if(result==None):
        return hash
    return result[0]

def getEvidenceName(hash):
    c=conn.cursor()
    c.execute("SELECT name FROM evidenceNames WHERE id=?",(hash,))
    # check it actally exists
    result=c.fetchone()
    if(result==None):
        return hash
    return result[0]

def addGroupName(groupName,name):
    c=conn.cursor()
    # check if the group already exists
    c.execute("SELECT * FROM groupNames WHERE id=?",(groupName,))
    if(len(c.fetchall())==0):
        c.execute("INSERT INTO groupNames VALUES (?,?)",(groupName,name))
    conn.commit()

def addEvidenceName(evidenceId,name):
    c=conn.cursor()
    # check if the group already exists
    c.execute("SELECT * FROM evidenceNames WHERE id=?",(evidenceId,))
    if(len(c.fetchall())==0):
        c.execute("INSERT INTO evidenceNames VALUES (?,?)",(evidenceId,name))
    conn.commit()

# Runner
if __name__ == '__main__':
    app.run()