sudo adduser biuser
sudo su - biuser
# mkdir .ssh
chmod 700 .ssh
cd .ssh
curl https://bds-public-keys.s3.us-east-1.amazonaws.com/biuser_kp.pub >> authorized_keys
chmod 600 authorized_keys
chown -R biuser:biuser /home/biuser/