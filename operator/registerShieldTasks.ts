import { ethers } from "ethers";
import * as dotenv from "dotenv";
const fs = require('fs');
const path = require('path');
dotenv.config();

// Setup env variables
const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
/// TODO: Hack
let chainId = 31337;

const avsDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../contracts/deployments/pool-vault-manager/${chainId}.json`), 'utf8'));
const poolVaultManagerAddress = avsDeploymentData.addresses.poolVaultManager;
const poolVaultManagerABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/PoolVaultManager2.json'), 'utf8'));
// Initialize contract objects from ABIs
const poolVaultManager = new ethers.Contract(poolVaultManagerAddress, poolVaultManagerABI, wallet);


// Function to generate random names
function generateRandomName(): string {
    const adjectives = ['Quick', 'Lazy', 'Sleepy', 'Noisy', 'Hungry'];
    const nouns = ['Fox', 'Dog', 'Cat', 'Mouse', 'Bear'];
    const adjective = adjectives[Math.floor(Math.random() * adjectives.length)];
    const noun = nouns[Math.floor(Math.random() * nouns.length)];
    const randomName = `${adjective}${noun}${Math.floor(Math.random() * 1000)}`;
    return randomName;
  }

async function registerShieldTask(taskName: string) {
  try {
    // Send a transaction to the createNewTask function
    const tx = await poolVaultManager.registerShield(
      "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c",
      -5000,
      5000,
      300,
      "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    );
    
    // Wait for the transaction to be mined
    const receipt = await tx.wait();
    
    console.log(`Transaction successful with hash: ${receipt.hash}`);
  } catch (error) {
    console.error('Error sending transaction:', error);
  }
}

// Function to create a new task with a random name every 15 seconds
function startCreatingTasks() {
  setInterval(() => {
    const randomName = generateRandomName();
    console.log(`Creating new task with name: ${randomName}`);
    registerShieldTask(randomName);
  }, 24000);
}

// Start the process
startCreatingTasks();
