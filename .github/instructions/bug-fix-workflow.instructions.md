---
applyTo: "**/*"
---

# Bug Fix Workflow for kitchen-chef-infra-agentless

## How to read a failure

All failures appear in `.kitchen/logs/kitchen.log` and
`.kitchen/logs/<instance>.log`. Start with the instance log for the actual error.

## Common failure patterns and fixes

### Pattern 1: `NoMethodError` / `undefined method`

Check if calling a private TKE method. Common culprit:
```
NoMethodError: private method 'state_file' called
```
**Fix**: Never call `instance.state_file`. Use the `state` hash passed as argument.
```ruby
# WRONG:
instance.state_file.read["some_key"]
# CORRECT:
state[:some_key]
```

### Pattern 2: `Docker Exec (127)` — command not found

Binary path is wrong or not on PATH.

**Chef 18 (chef/chef image)**:
```
/opt/chef/bin/chef-client
```
**Chef 19+ (chef/chef-hab image)**:
```
/hab/pkgs/chef/chef-infra-client/*/*/bin/chef-client   ← glob, needs sh -c
```
**Fix**: Check `default_config :chef_binary` in `chef_infra_agentless.rb`. The glob path must be wrapped in `sh -c "..."`.

### Pattern 3: Shell operators not working (`|`, `>`, `&&`)

`Dokken::Connection#execute` calls Docker exec API directly — **no shell**.
Symptoms: `echo key | base64 -d > file` writes the literal string `key | base64 -d > file` to stdout.

**Fix**: Wrap in `sh -c '...'`:
```ruby
# WRONG:
conn.execute("echo #{encoded} | base64 -d > /root/.ssh/key")
# CORRECT:
conn.execute("sh -c 'echo #{encoded} | base64 -d > /root/.ssh/key'")
```
Same applies to `&&`, `>>`, `$(...)`.

### Pattern 4: `PrivateKeyMissing` / chef-client tries to register with Chef Server

chef-client is not running in local mode. It's trying to connect to a Chef Server.

**Fix**: Ensure `--local-mode` and `--config <root>/client.rb` are in `build_target_command`:
```ruby
parts << "--config #{root}/client.rb"
parts << "--local-mode"
```

### Pattern 5: `Missing Cookbooks: No such cookbook: <name>`

The cookbook sandbox doesn't contain the cookbook. `CommonSandbox` looks for
`<kitchen_root>/cookbooks/` hardcoded.

**Fix**:
1. Ensure `cookbooks/` symlink exists at repo root: `ln -sf kitchen_tests/cookbooks cookbooks`
2. Ensure `cookbooks_path: kitchen_tests/cookbooks` is in `kitchen.yml` provisioner block

### Pattern 6: SSH readiness check fails (`TCPSocket::...`)

`TCPSocket.new(container_ip, 22)` from macOS host fails. Docker Desktop puts
container IPs inside a Linux VM — unreachable from macOS process.

**Fix**: Check SSH readiness from *inside* the container:
```ruby
result = Mixlib::ShellOut.new("docker exec #{container_name} ss -tlnp").tap(&:run_command)
return if result.stdout.include?(":22")
```

### Pattern 7: `ArgumentError: Credentials file does not exist`

Wrong credentials path. `chef-client --target` mode reads from
`~/.chef/target_credentials`, not `~/.chef/credentials`.

**Fix**: Check `REMOTE_CREDENTIALS_PATH` constant in `credential_provisioner.rb`:
```ruby
REMOTE_CREDENTIALS_PATH = "~/.chef/target_credentials"
```

### Pattern 8: `train-docker gem not found` / `Docker URI not supported`

`docker://container-name` URIs require `train-docker` gem, which is NOT bundled
in any Chef image (only `train-core` is available).

**Fix**: Use SSH transport for container-mode nodes. The `TargetUriBuilder` should
return `ssh://root@<ip>:22` for container nodes, never `docker://`.

### Pattern 9: `Connection refused` on remote container SSH

Remote container is on the wrong Docker network. Must be on `dokken` network
(same as the source container).

**Fix**: In `ContainerNodeManager#start`, add `--network dokken`:
```ruby
run_cmd = ["docker", "run", "-d", "--name", container_name,
           "--network", Kitchen::Agentless::ContainerNodeManager::DOKKEN_NETWORK,
           node.test_kitchen_image]
```

### Pattern 10: `InSpec Runner returns 1` during `kitchen verify`

InSpec is running against the **source container**, not the remote nodes.
The agentless verify epic (targeting remote nodes) is not yet implemented.

**Workaround**: Comment out `verifier.inspec_tests` in `kitchen.yml` until
remote-node verification is implemented.

## Debug commands

```bash
# See what's on the source container
docker exec <source-container-name> ls /tmp/kitchen/
docker exec <source-container-name> cat /tmp/kitchen/client.rb
docker exec <source-container-name> cat ~/.chef/target_credentials

# Check remote container SSH
docker exec <remote-container-name> ss -tlnp
docker inspect --format '{{(index .NetworkSettings.Networks "dokken").IPAddress}}' <name>

# Full kitchen debug
bundle exec kitchen --log-level debug converge 2>&1 | tee /tmp/kitchen-debug.log
```

## After fixing

```bash
bundle exec rake unit                           # must be 0 failures
bundle exec cookstyle --chefstyle lib/ spec/   # must be 0 offenses
bundle exec kitchen destroy && bundle exec kitchen converge   # end-to-end
```
