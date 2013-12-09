# Author:: Frank Breedijk <fbreedijk@schubergphilis.com>
# Copyright:: Copyright (c) 2013
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


module ApiLib
  require 'rubygems'
  begin
    require 'cloudstack_helper'
  rescue LoadError
    Chef::Log.fatal "Unable to load cloudstack_helper gem, this run will likely fail"
  end
  require 'json'

  def setup_csapi(url='',apikey='',seckey='')
    if ( url !~ /^https?\:\/\/.*\/api\/$/ ) then
      abort("Malformed Cloudstack API url")
    else
      if ( apikey == '' || seckey=='' ) then
        abort("No API key or SECRET key provided")
      end
    end

    return  CloudStackHelper.new(:api_url => url,:api_key => apikey,:secret_key => seckey)
  end

  def csapi_do(api = nil,params = nil, abort_on_error = false, wait_for_async = false)
    if ( api == nil || params == nil ) then
      abort("No api object or parameter block provided")
    end

    params[:response] = 'json'

    json = ""
    begin
      json = api.get(params).body
    rescue
      error = "Cloud Stack API returned an error: #{$!}"
      Chef::Log.error(error)
      if ( abort_on_error ) then
        abort(error)
      else
        return nil
      end
    end

    reply = JSON.parse(json)
    if ( wait_for_async )
      # Foind out job id
      jobid = nil
      reply.each do |key, val|
        if ( jobid == nil ) then
          jobid = val["jobid"]
        end
      end

      if ( jobid == nil ) then
        Chef::Log.fatal("Unable to find jobid, result: #{result}")
        exit
      else
        params = {
          :command => "queryAsyncJobResult",
          :jobid => jobid
        }
        status = csapi_do(api,params)["queryasyncjobresultresponse"]
        while ( status["jobstatus"] == 0 ) do 
          Chef::Log.info("Status of job #{jobid} is #{status["jobstatus"]}")
          sleep 1
          status = csapi_do(api,params)["queryasyncjobresultresponse"]
        end
        Chef::Log.info("Job #{jobid} done, result: #{status["jobresult"]}.")
        reply = status
      end
    end
    
    return reply
  end
end
