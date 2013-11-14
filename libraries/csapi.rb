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
  require 'cloudstack_helper'
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

  def csapi_do(api = nil,params = nil, abort_on_error = false)
    if ( api == nil || params == nil ) then
      abort("No api object or parameter block provided")
    end

    params[:response] = 'json'

    json = ""
    begin
      json = api.get(params).body
    rescue
      error = "Cloud Stck API returned an error: #{$!}"
      Chef::Log.error(error)
      if ( abort_on_error ) then
        abort(error)
      else
        return nil
      end
    end

    return JSON.parse(json)
  end
end
