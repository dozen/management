authorized_keys_dir = File.expand_path('../../files', File.dirname(__FILE__))
authorized_keys_local = File.join(authorized_keys_dir, 'authorized_keys.local')
authorized_keys_file = if File.exist?(authorized_keys_local)
                         authorized_keys_local
                       else
                         File.join(authorized_keys_dir, 'authorized_keys')
                       end
codex_version = '0.142.5'
admin_users = Array(node[:admin_users])
normal_users = Array(node[:users])
password_hashes = node[:password_hashes] || {}
all_users = (admin_users + normal_users).uniq

all_users.each do |user_name|
  execute "create #{user_name} user" do
    command "useradd -m -s /bin/bash -U #{user_name}"
    not_if "id -u #{user_name} >/dev/null 2>&1"
  end

  password_hash = password_hashes[user_name.to_sym] || password_hashes[user_name.to_s]
  if password_hash
    password_hash_file = "/run/mitamae-password-hash-#{user_name}"

    file password_hash_file do
      owner 'root'
      group 'root'
      mode '600'
      content password_hash
      sensitive true
    end

    execute "set #{user_name} password hash" do
      command "usermod -p \"$(cat #{password_hash_file})\" #{user_name}"
      not_if "test \"$(awk -F: '/^#{user_name}:/{print $2}' /etc/shadow)\" = \"$(cat #{password_hash_file})\""
    end

    execute "remove #{user_name} password hash file" do
      command "rm -f #{password_hash_file}"
      only_if "test -f #{password_hash_file}"
    end
  end
end

directory '/etc/sudoers.d' do
  owner 'root'
  group 'root'
  mode '755'
end

file '/etc/sudoers.d/10-wheel' do
  owner 'root'
  group 'root'
  mode '440'
  content "%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n"
  notifies :run, 'execute[validate sudoers]', :immediately
end

execute 'validate sudoers' do
  command 'visudo -cf /etc/sudoers'
  action :nothing
end

admin_users.each do |user_name|
  execute "add #{user_name} to wheel" do
    command "usermod -aG wheel #{user_name}"
    not_if "id -nG #{user_name} | grep -qw wheel"
  end

  directory "/home/#{user_name}/.ssh" do
    owner user_name
    group user_name
    mode '700'
  end

  file "/home/#{user_name}/.ssh/authorized_keys" do
    owner user_name
    group user_name
    mode '600'
    content File.read(authorized_keys_file)
  end

  execute "ensure #{user_name} local bin path" do
    command "grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' /home/#{user_name}/.bashrc || printf '\\nexport PATH=\"$HOME/.local/bin:$PATH\"\\n' >> /home/#{user_name}/.bashrc"
    not_if "grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' /home/#{user_name}/.bashrc"
  end

  directory "/home/#{user_name}/.local" do
    owner user_name
    group user_name
    mode '755'
  end

  directory "/home/#{user_name}/.local/bin" do
    owner user_name
    group user_name
    mode '755'
  end

  execute "install codex for #{user_name}" do
    command "su - #{user_name} -c 'npm install -g --prefix ~/.local @openai/codex@#{codex_version}'"
    not_if "su - #{user_name} -c 'npm list -g --prefix ~/.local --depth=0 @openai/codex 2>/dev/null | grep -q \"@openai/codex@#{codex_version}\"'"
  end
end
