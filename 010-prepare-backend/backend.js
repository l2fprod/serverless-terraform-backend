const COS = require('ibm-cos-sdk');
const querystring = require('querystring');

const EMPTY_STATE = {
  version: 3,
  serial: 0,
  modules: [{
    path: ['root'],
    outputs: {},
    resources: {}
  }]
};

function makeFilename(env) {
  if (env) {
    return `states/named/${env}.tfstate`;
  } else {
    return `states/default.tfstate`;
  }
}

function makeVersionFilename(env, serial) {
  if (env) {
    return `versions/named/${env}-${serial}.tfstate`;
  } else {
    return `versions/default-${serial}.tfstate`;
  }
}

function makeLockFilename(env) {
  if (env) {
    return `locks/named/${env}.lock`;
  } else {
    return `locks/default.lock`;
  }
}

function extractBodyFromParams(params) {
  return JSON.parse(Buffer.from(params.__ow_body, 'base64').toString('utf-8'));
}

function returnFailure(statusCode, errorBody) {
  return {
    headers: {
      'Content-Type': 'application/json'
    },
    statusCode,
    body: Buffer.from(JSON.stringify(errorBody, null, 2)).toString('base64'),
  };
}

/**
 * Primitives to work with Cloud Object Storage
 */
class Storage {
  constructor(endpoint, apiKeyId, serviceInstanceId, bucket) {
    console.log('Initializing COS.S3', endpoint, serviceInstanceId, bucket);
    this.cos = new COS.S3({
      endpoint,
      apiKeyId,
      serviceInstanceId,
    });
    this.bucket = bucket;
  }

  /**
   * Returns the given object
   * 
   * @param {string} filename 
   */
  load(filename) {
    console.log(`Loading cos://${this.bucket}/${filename}`);
    return this.cos.getObject({
      Bucket: this.bucket,
      Key: filename,
    }).promise().then((data) => {
      return JSON.parse(data.Body.toString());
    }).catch((err) => {
      if (err.code === 'NoSuchKey') {
        return null;
      } else {
        console.log('error', err);
        throw err;
      }
    });
  }

  /**
   * Stores the JSON representation of the given Object under the given name
   * 
   * @param {string} filename 
   * @param {object} content 
   */
  save(filename, content) {
    console.log(`Storing cos://${this.bucket}/${filename}`);
    return this.cos.putObject({
      Bucket: this.bucket,
      Key: filename,
      Body: JSON.stringify(content),
      ContentType: 'application/json',
    }).promise();
  }

  /**
   * Deletes the given file
   * 
   * @param {string} filename 
   */
  delete(filename) {
    console.log(`Deleting cos://${this.bucket}/${filename}`);
    return this.cos.deleteObject({
      Bucket: this.bucket,
      Key: filename,
    }).promise();
  }
}

class State {

  constructor(storage, env, versioning) {
    this.storage = storage;
    this.env = env;
    this.versioning = versioning;
  }

  async lock(lockInfo) {
    const lockFilename = makeLockFilename(this.env);
    const currentLock = await this.storage.load(lockFilename);
    if (currentLock) {
      console.log('State is already locked', currentLock);
      const err = new Error();
      err.code = 409;
      err.body = currentLock;
      throw err;
    } else {
      // lock the state
      console.log('Locking state...', lockInfo);
      await this.storage.save(lockFilename, lockInfo);
    }
  }

  unlock() {
    return this.storage.delete(makeLockFilename(this.env));
  }

  get() {
    const stateFilename = makeFilename(this.env);
    return this.storage.load(stateFilename);
  }

  async post(newState, requesterId) {
    const lockFilename = makeLockFilename(this.env);
    const currentLock = await this.storage.load(lockFilename);
    if (currentLock) {
      console.log(`State is current locked by ID=${currentLock.ID}`)
      console.log(`ID=${requesterId} is requesting to update the state`);
      if (requesterId !== currentLock.ID) {
        const err = new Error();
        err.code = 409;
        err.body = currentLock;
        throw err;
      }
    }

    if (this.versioning) {
      const currentState = await this.get();
      if (currentState) {
        // save a copy
        const versionFilename = makeVersionFilename(this.env, currentState.serial);
        await this.storage.save(versionFilename, currentState);
      }
    }

    const stateFilename = makeFilename(this.env);
    await this.storage.save(stateFilename, newState);
  }
}

async function main(params) {
  const queryParams =  params.__ow_query ? querystring.parse(params.__ow_query) : {};
  if (queryParams.debug) {
    console.log(params);
  }

  // extract the API key from the authorization header username=cos password=apikey
  if (!params.__ow_headers.authorization) {
    return returnFailure(401, { error: 'missing authentication' });
  }

  const authElements = Buffer.from(params.__ow_headers.authorization.split(' ')[1], 'base64').toString().split(':');
  if (authElements[0] !== 'cos') {
    return returnFailure(401, { error: 'invalid username' });    
  }

  const storage = new Storage(
    params['services.storage.apiEndpoint'],
    authElements[1],
    params['services.storage.instanceId'],
    params['services.storage.bucket']
  );

  const state = new State(storage, queryParams.env, queryParams.versioning);

  try {
    let resultBody;

    switch (params.__ow_method) {
      case 'get': {
        const currentState = await state.get();
        resultBody = currentState ? currentState : EMPTY_STATE;
        break;
      }
      case 'post': {
        const newState = extractBodyFromParams(params);
        await state.post(newState, queryParams.ID)
        resultBody = newState;
        break;
      }
      case 'put': {
        const lockInfo = extractBodyFromParams(params);
        await state.lock(lockInfo);
        resultBody = lockInfo;
        break;
      }
      case 'delete': {
        await state.unlock();
        resultBody = {};
        break;
      }
      default: {
        throw new Error(`Unknown method ${params.__ow_method}`)
      }
    }

    return {
      headers: {
        'Content-Type': 'application/json'
      },
      body: Buffer.from(JSON.stringify(resultBody, null, 2)).toString('base64'),
    };
  } catch (err) {
    console.log('Failed to process method', err);

    let statusCode = 500;
    let errorBody = { ok: false }

    if (err.code) {
      statusCode = err.code;
      errorBody = err.body;
    }

    return {
      headers: {
        'Content-Type': 'application/json'
      },
      statusCode,
      body: Buffer.from(JSON.stringify(errorBody, null, 2)).toString('base64'),
    };
  }
}