// Read-only baseline preflight. Never clones over, resets or cleans an existing worktree.
import {execFileSync} from 'node:child_process';import {createHash} from 'node:crypto';
const git=(...args)=>execFileSync('git',args,{encoding:'utf8'}).trim();
const status=git('status','--porcelain'),root=git('rev-parse','--show-toplevel'),branch=git('branch','--show-current'),sha=git('rev-parse','HEAD');
const snapshot=()=>createHash('sha256').update(git('diff','--binary')).update(git('status','--porcelain')).digest('hex');const before=snapshot();
const result={root,branch,sha,state:status?'EXISTING_DIRTY_WORKTREE':'EXISTING_CLEAN_WORKTREE',action:status?'PRESERVE_ALL_CHANGES_AND_INSPECT_OWNERSHIP_BEFORE_EDITING':'REUSE_VERIFIED_CHECKOUT',clonePermitted:false,resetOrCleanPermitted:false,workingSnapshot:before};
if(snapshot()!==before)throw Error('CONCURRENT_WORKTREE_CHANGE');console.log(JSON.stringify(result,null,2));
