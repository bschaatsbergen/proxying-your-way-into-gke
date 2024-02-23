sudo apt-get update -y
sudo apt-get install -y tinyproxy
sudo mkdir -p /etc/systemd/system/tinyproxy.service.d/
echo -e '[Service]\nRestart=always' | sudo tee /etc/systemd/system/tinyproxy.service.d/override.conf
echo -e 'Allow localhost' | sudo tee -a /etc/tinyproxy/tinyproxy.conf
sudo systemctl daemon-reload
sudo systemctl restart tinyproxy
