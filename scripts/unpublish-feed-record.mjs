#!/usr/bin/env node
import {readFileSync} from 'node:fs'
const args=process.argv.slice(2), checkOnly=args[0]==='--check'
const [did,rkey]=checkOnly?args.slice(1):args
const collection='app.bsky.feed.generator'
async function jsonRequest(url,options={}){const response=await fetch(url,options);const data=await response.json().catch(()=>({}));return{response,data}}
if(!did||!/^did:plc:[a-z2-7]+$/.test(did)||!rkey||! /^[a-zA-Z0-9._:-]+$/.test(rkey)){console.error('Parâmetros de DID ou rkey inválidos.');process.exit(1)}
async function main(){
 const result=await jsonRequest('https://plc.directory/'+did)
 if(!result.response.ok||result.data.id!==did)throw new Error('Não foi possível validar o DID do publicador.')
 const services=Array.isArray(result.data.service)?result.data.service:[]
 const item=services.find(x=>x?.id==='#atproto_pds'||String(x?.id??'').endsWith('#atproto_pds'))
 const pds=String(item?.serviceEndpoint??'').replace(/\/+$/,'')
 if(new URL(pds).protocol!=='https:')throw new Error('O DID do publicador não informa PDS HTTPS válido.')
 const recordUrl=new URL(pds+'/xrpc/com.atproto.repo.getRecord')
 recordUrl.searchParams.set('repo',did);recordUrl.searchParams.set('collection',collection);recordUrl.searchParams.set('rkey',rkey)
 const record=await jsonRequest(recordUrl)
 if(checkOnly){if(record.response.ok)console.log('record-present');else if(record.data.error==='RecordNotFound')console.log('record-absent');else throw new Error('Não foi possível verificar o registro público.');return}
 const parts=readFileSync(0,'utf8').split('\0')
 const identifier=String(parts[0]??'').trim().replace(/^@/,''),password=String(parts[1]??'').trim()
 if(!identifier||!password)throw new Error('Handle e App Password são obrigatórios.')
 const login=await jsonRequest(pds+'/xrpc/com.atproto.server.createSession',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({identifier,password})})
 if(!login.response.ok||!login.data.accessJwt||login.data.did!==did)throw new Error('Autenticação recusada ou a conta não é dona do registro.')
 try{
  const removal=await jsonRequest(pds+'/xrpc/com.atproto.repo.deleteRecord',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+login.data.accessJwt},body:JSON.stringify({repo:did,collection,rkey})})
  if(!removal.response.ok&&removal.data.error!=='RecordNotFound')throw new Error('A API não aceitou a remoção do registro.')
  console.log('Registro do Feed Generator removido ou já inexistente.')
 }finally{await fetch(pds+'/xrpc/com.atproto.server.deleteSession',{method:'POST',headers:{authorization:'Bearer '+login.data.accessJwt}}).catch(()=>{})}
}
main().catch(error=>{console.error(error instanceof Error?error.message:'Falha ao remover registro.');process.exitCode=1})
