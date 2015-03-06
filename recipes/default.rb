#
# Cookbook Name:: instance-tagging-and-naming
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

chef_gem 'aws-sdk' do
  version node['aws']['aws_sdk_version']
  action :install
end
include_recipe "aws"

aws_resource_tag node['ec2']['instance_id'] do
	tags({
		"chef-loaded" => "true",
	      	"chef-enviroment" => node.chef_environment
	})
	action :update
end

chef_gem 'aws-sdk' do
  version node['aws']['aws_sdk_version']
  action :install
end

require 'aws-sdk'


ruby_block "setting tags on ebs" do
	block do
		## Get the AZ we're working in from the meta-data
		availability_zone = node['ec2']['placement_availability_zone']
		region = availability_zone[0,availability_zone.length - 1]
		fail 'Cannot find the availability zone!' unless region

		Chef::Log.info("** AZ is " + availability_zone)
		Chef::Log.info("** Region is " + region)
		Chef::Log.info("** instance_id is "+ node['ec2']['instance_id'])

		## Create the EC2 object
		ec2 = Aws::EC2::Client.new(region: region)


		## Try to get the volumes for this EC2 instance
		begin
			resp = ec2.describe_volumes(
				filters: [{
					name: "attachment.instance-id",
					values: ["#{node['ec2']['instance_id']}"]
				}]
			)
		rescue => e
			Chef::Log.error("Failed to get the volume information for #{node['ec2']['instance_id']}: #{e.message}")
		end

		## Try to get the current tags for this EC2 instance.  We'll fail to some
		## defaults if we're not able, but it's not a good place to be. 

		begin
			describeTagsResp = ec2.describe_tags(
				filters: [{
					name: "resource-id",
					values: ["#{node['ec2']['instance_id']}"]
				}, {
					name: "key",
					values: ["owner", "billing"]
				}]
			)

			## Create the array of tags we'll create for each of the volumes
			volume_tags_array = []
			describeTagsResp.tags.each do |tag|
				volume_tags_array << {key: "#{tag.key}", value: "#{tag.value}"}
				Chef::Log.info("Creating tag #{tag.key}: #{tag.value}")
			end

			## Add the name tag, using the instance_id in the node
			volume_tags_array << {key: "Name", value: "Volume for #{node['ec2']['instance_id']}"}

		rescue => e
			Chef::Log.error("Failed to get tags for instnace #{node['ec2']['instance_id']}: #{e.message}")
		end
					

		
		## Go through the volume information and start tagging the things
		fail "No resp object!" unless resp	
		resp.volumes.each do |volume|
			Chef::Log.info("** Found attached volume '#{volume.volume_id}'")
			
			begin
			tagsResp = ec2.create_tags(
				resources: ["#{volume.volume_id}"],
				tags: volume_tags_array
			)
			rescue Aws::EC2::Errors::InvalidVolumeNotFound => e
				Chef::Log.error("Failed to create tag for #{volume.volume_id}: #{e.message}")
			end
		end
	end
	action :run
end
	

