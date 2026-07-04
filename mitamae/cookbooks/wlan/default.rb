wlan = node[:wlan] || {}
wlan_ssid = wlan[:ssid]
wlan_passphrase = wlan[:passphrase]
wlan_profile = node[:wlan_iwd_profile] || "#{wlan_ssid}.psk"

raise 'secrets/secrets.yml に wlan.ssid がありません' if wlan_ssid.nil? || wlan_ssid.empty?
raise 'secrets/secrets.yml に wlan.passphrase がありません' if wlan_passphrase.nil? || wlan_passphrase.empty?

package 'wpa_supplicant' do
  action :remove
end

execute 'disable wpa_supplicant units' do
  command 'systemctl disable --now wpa_supplicant.service wpa_supplicant@wlan0.service 2>/dev/null || true'
  only_if "systemctl list-unit-files 'wpa_supplicant*' --no-legend 2>/dev/null | grep -q ."
end

execute 'remove wpa_supplicant configuration' do
  command 'rm -rf /etc/wpa_supplicant'
  only_if 'test -e /etc/wpa_supplicant'
end

package 'iwd' do
  action :install
end

directory '/etc/iwd' do
  owner 'root'
  group 'root'
  mode '755'
end

file '/etc/iwd/main.conf' do
  owner 'root'
  group 'root'
  mode '644'
  content "[General]\nEnableNetworkConfiguration=false\n\n[DriverQuirks]\nPowerSaveDisable=brcmfmac\n"
  notifies :restart, 'service[iwd]'
end

directory '/var/lib/iwd' do
  owner 'root'
  group 'root'
  mode '700'
end

file "/var/lib/iwd/#{wlan_profile}" do
  owner 'root'
  group 'root'
  mode '600'
  content "[Security]\nPassphrase=#{wlan_passphrase}\n"
  sensitive true
  not_if "test -f /var/lib/iwd/#{wlan_profile}"
  notifies :restart, 'service[iwd]'
end

file '/etc/systemd/network/wlan.network' do
  owner 'root'
  group 'root'
  mode '644'
  content "[Match]\nName=wlan*\n\n[Link]\nRequiredForOnline=no\n\n[Network]\nDHCP=yes\nDNSSEC=no\n"
  notifies :restart, 'service[systemd-networkd]'
end

service 'iwd' do
  action [:enable, :start]
end

service 'systemd-networkd' do
  action [:enable, :start]
end
